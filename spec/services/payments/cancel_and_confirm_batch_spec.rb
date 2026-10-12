require "rails_helper"

# B01b §5 "Après l'export": to change an exported batch it is cancelled (with a reason) and another one is made; the person says when they loaded the file in their bank.
RSpec.describe "Cancelling a payment batch and saying it was loaded in the bank" do
  include_context "with approvable batch"

  let(:exporter) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader) { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:invoice) { posted }
  let(:batch) { approved_batch(invoice) }

  def exported!
    Payments::ExportBatch.call(batch: batch, user: exporter, recent_second_factor: true).tap { |r| raise r.message if r.failure? }
    batch.reload
  end

  def cancel(target = batch, reason: "Wrong date", user: exporter) = Payments::CancelBatch.call(batch: target, user: user, reason: reason)

  def confirm(target = batch, user: exporter) = Payments::ConfirmSubmission.call(batch: target, user: user)

  def audit(action) = Accounting::AuditLog.for_record(batch).for_action(action)

  def held? = Payments::ItemInvoice.where(item_id: batch.items.select(:id)).pluck(:active).all?

  describe "before the file was made" do
    it "gives up the batch with the reason, frees its invoices and lets another batch take them" do
      result = cancel

      expect(result).to be_success
      expect(batch.reload).to have_attributes(status: "cancelled", cancel_reason: "Wrong date", cancelled_by: exporter)
      expect(batch.cancelled_at).to eq(Time.current)
      expect(Payments::ItemInvoice.where(item_id: batch.items.select(:id)).pluck(:active)).to all(be(false))
      expect(audit("payment_batch_cancelled").sole.payload).to include("reason" => "Wrong date", "from" => "approved")
      expect(batch_of(invoice)).to be_draft
    end

    it "closes the approval that was waiting" do
      approved_batch # makes the policy
      draft = batch_of(posted(unit_price: 70))
      Payments::SubmitBatch.call(batch: draft, user: preparer)

      cancel(draft)

      expect(draft.reload.approval_request).to be_cancelled
    end

    it "needs a reason, the right to prepare, and the feature" do
      expect(cancel(reason: " ")).to be_failure
      expect(cancel(user: reader)).to be_failure
      entity.update!(features: entity.features.merge("b01b" => false))
      expect(cancel(batch.reload)).to be_failure
      expect(batch.reload).to be_approved
    end
  end

  describe "after the file was made" do
    before { exported! }

    it "is only asked for: the invoices stay held until the person says the file was not, or is no longer, authorized in the bank" do
      expect(cancel).to be_success

      expect(batch.reload).to be_cancel_requested
      expect(held?).to be(true)
      expect(audit("payment_batch_cancel_requested").sole.payload).to include("reason" => "Wrong date")
    end

    it "is completed by the person who confirms, and then the invoices are free" do
      cancel
      result = Payments::ConfirmCancellation.call(batch: batch, user: exporter)

      expect(result).to be_success
      expect(batch.reload).to be_cancelled
      expect(Payments::ItemInvoice.where(item_id: batch.items.select(:id)).pluck(:active)).to all(be(false))
      expect(audit("payment_batch_cancelled").count).to eq(1)
    end

    it "does not complete what was not asked for" do
      expect(Payments::ConfirmCancellation.call(batch: batch, user: exporter)).to be_failure
    end

    it "keeps the file as it was" do
      kept = batch.file_sha256
      cancel

      expect(batch.reload.file_sha256).to eq(kept)
    end
  end

  describe "saying the file was loaded in the bank" do
    before { exported! }

    it "makes the batch submitted, with who and when" do
      result = confirm

      expect(result).to be_success
      expect(batch.reload).to have_attributes(status: "submitted", submitted_by: exporter, submitted_at: Time.current)
      expect(audit("payment_batch_submitted").sole.payload).to include("sha256" => batch.file_sha256, "payments" => 1)
      expect(held?).to be(true)
    end

    it "is said once, and by a person who may" do
      expect(confirm(user: reader)).to be_failure
      confirm

      expect(confirm).to be_failure
    end

    it "only for a batch whose file exists" do
      draft = batch_of(posted(unit_price: 30))

      expect(confirm(draft)).to be_failure
    end

    it "can still be cancelled, by request" do
      confirm

      expect(cancel).to be_success
      expect(batch.reload).to be_cancel_requested
    end
  end

  it "does not cancel a batch that was paid" do
    exported!
    confirm
    batch.update_columns(status: Payments::Batch.statuses[:debited])

    expect(cancel).to be_failure
  end
end

require "rails_helper"

# B01b §5 "Génération du fichier" and "Après l'export": an approved batch, a recent second factor, a pre-flight that still holds; the file is kept as it was
# made, the batch is frozen, and everything is in the audit trail.
RSpec.describe Payments::ExportBatch do
  include_context "with approvable batch"

  let(:batch) { approved_batch }
  let(:exporter) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  def export(user: exporter, second_factor: true, target: batch) = described_class.call(batch: target, user: user, recent_second_factor: second_factor)

  def audit(action) = Accounting::AuditLog.for_record(batch).for_action(action)

  describe "an approved batch" do
    it "makes the file, keeps it as a document of the company, and freezes the batch with what the person compares to the bank" do
      result = export

      expect(result).to be_success
      batch.reload
      expect(batch).to be_exported
      expect(batch).to have_attributes(exported_by: exporter, exported_at: Time.current, message_id: batch.reference, format_version: "pain.001.001.03", control_sum: batch.total)
      document = batch.document
      expect(document.file.download).to eq(result[:file])
      expect(batch.file_sha256).to eq(Digest::SHA256.hexdigest(result[:file])).and eq(document.sha256)
      expect(audit("payment_batch_exported").sole.payload).to include("sha256" => batch.file_sha256, "payments" => 1, "total" => "1210.00", "message_id" => batch.reference)
    end

    it "can be made again from the batch: the same bytes as the file kept" do
      result = export

      again = Payments::Sepa::Pain001Builder.call(batch.reload, created_at: batch.exported_at)

      expect(Digest::SHA256.hexdigest(again)).to eq(batch.file_sha256)
      expect(again).to eq(result[:file])
    end

    it "is done once" do
      export
      kept = batch.reload.file_sha256

      again = export

      expect(again).to be_failure
      expect(batch.reload.file_sha256).to eq(kept)
      expect(Accounting::Document.where(origin: :payment_file).count).to eq(1)
    end
  end

  describe "what it asks for" do
    it "the right to export" do
      result = export(user: create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) })

      expect(result).to be_failure
      expect(batch.reload).to be_approved
    end

    it "a second factor given a moment ago" do
      result = export(second_factor: false)

      expect(result[:code]).to eq(:step_up_required)
      expect(batch.reload).to be_approved
    end

    it "a batch that is approved, not a draft or one waiting" do
      draft = batch_of(posted(unit_price: 50))

      expect(export(target: draft)).to be_failure
    end

    it "the feature to be on" do
      batch
      entity.update!(features: entity.features.merge("b01b" => false))

      expect(export).to be_failure
    end

    it "an approval of the batch as it is now" do
      batch.update_columns(total: batch.total + 1)

      result = export

      expect(result[:code]).to eq(:content_changed)
      expect(batch.reload).to be_approved
    end

    it "a pre-flight that still holds: an account blocked since the approval stops the file" do
      batch
      account.update_columns(status: Accounting::PartnerBankAccount.statuses[:blocked])

      result = export

      expect(result).to be_failure
      expect(result.message).to match(/bank account/i)
      expect(batch.reload).to be_approved
      expect(Accounting::Document.where(origin: :payment_file)).to be_empty
    end

    it "a bank profile that names a version the builder knows" do
      batch.update!(bank_profile: nil)

      expect(export).to be_failure
      expect(batch.reload).to be_approved
    end
  end

  describe "after the export" do
    before { export }

    it "does not let the batch change: neither its amounts, nor its date, nor its account, nor its file" do
      batch.reload

      expect { batch.update!(total: 1) }.to raise_error(ActiveRecord::RecordInvalid, /exported/)
      expect { batch.update!(requested_execution_date: execution + 1) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { batch.update!(file_sha256: "0" * 64) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "does not let a payment change or go away" do
      item = batch.reload.items.first

      expect { item.update!(amount: 1) }.to raise_error(ActiveRecord::RecordInvalid, /exported/)
      expect { item.update!(iban: "BE71096123456769") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { item.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end

    it "keeps the invoices held" do
      expect(Payments::ItemInvoice.where(item_id: batch.items.select(:id)).pluck(:active)).to all(be(true))
    end
  end
end

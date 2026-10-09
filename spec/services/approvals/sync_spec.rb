require "rails_helper"

# B01a §4.5: an approval holds for one content. A significant change invalidates it and the circuit starts again.
RSpec.describe Approvals::Sync do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:author)      { create(:user) }
  let(:owner)       { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:invoice) do
    create(:invoice, :supplier, created_by: author, fiscal_year: fiscal_year).tap do |i|
      create(:invoice_line, invoice: i, account: create(:account), unit_price: "1000.00")
    end
  end
  let!(:policy) do
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1, conditions: { "min_amount" => "500" }).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
    end
  end

  def audit(action) = Accounting::AuditLog.for_record(invoice).for_action(action)

  def approve!(request)
    Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint)
  end

  let!(:request) { Approvals::Submit.call(invoice: invoice, user: author)[:request] }

  context "after the invoice was approved" do
    before { approve!(request) }

    it "invalidates the approval and starts again from the first level when the amount changes" do
      invoice.lines.first.update!(unit_price: "1500.00")

      expect(request.reload).to be_invalidated
      expect(request.invalidation_reason).to match(/content/i)
      fresh = Approvals::Request.pending.sole
      expect(fresh).to have_attributes(subject: invoice, current_step: 1, content_fingerprint: Approvals::ContentFingerprint.call(invoice))
      expect(invoice.reload).to be_payment_to_approve
      expect(audit("approval_invalidated").count).to eq(1)
    end

    it "does the same when the supplier, a due date, a line or a document changes" do
      invoice.update!(due_date: invoice.due_date + 10)
      expect(request.reload).to be_invalidated

      newest = Approvals::Request.pending.sole
      create(:invoice_line, invoice: invoice, account: invoice.lines.first.account, unit_price: "10.00")
      expect(newest.reload).to be_invalidated

      newest = Approvals::Request.pending.sole
      Accounting::DocumentLink.create!(document: create(:document), target: invoice)
      expect(newest.reload).to be_invalidated
    end

    it "leaves the approval alone when only a free label changes" do
      invoice.update!(description: "Reworded", notes: "Called them")
      invoice.lines.first.update!(description: "Consulting, October")

      expect(request.reload).to be_approved
      expect(invoice.reload).to be_payment_approved
      expect(audit("approval_invalidated")).to be_empty
    end

    it "leaves the approval alone when the invoice is validated and numbered" do
      invoice.update_columns(invoice_number: "ACH2026/0001")
      Approvals::Sync.call(invoice)

      expect(request.reload).to be_approved
    end

    it "records that no approval is needed any more when the change takes the invoice out of every policy" do
      invoice.lines.first.update!(unit_price: "100.00") # 121.00, under the minimum

      expect(request.reload).to be_invalidated
      expect(Approvals::Request.pending).to be_empty
      expect(invoice.reload).to be_payment_not_required
    end
  end

  context "while the request is still waiting" do
    it "starts again on the new content, so nobody approves what they have not seen" do
      invoice.lines.first.update!(unit_price: "2000.00")

      expect(request.reload).to be_invalidated
      expect(Approvals::Request.pending.sole.content_fingerprint).not_to eq(request.content_fingerprint)
      expect(Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint)).to be_failure
    end
  end

  it "does nothing for an invoice that never went through approval" do
    other = create(:invoice, :supplier, fiscal_year: fiscal_year)

    expect { create(:invoice_line, invoice: other, account: create(:account), unit_price: "900.00") }.not_to change(Approvals::Request, :count)
  end

  it "does nothing when the feature is off" do
    entity.update!(features: entity.features.merge("b01a" => false))
    invoice.lines.first.update!(unit_price: "3000.00")

    expect(request.reload).to be_pending
  end

  it "works outside any tenant, where seeders and jobs save invoices and lines" do
    invoice
    request

    expect do
      ActsAsTenant.without_tenant do
        Accounting::InvoiceLine.create!(entity: entity, invoice: invoice, account: invoice.lines.first.account, description: "Extra", unit_price: "10.00")
        invoice.update!(due_date: invoice.due_date + 3)
      end
    end.not_to raise_error
    expect(request.reload).to be_invalidated
  end
end

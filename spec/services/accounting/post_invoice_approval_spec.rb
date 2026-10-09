require "rails_helper"

# B01a: posting a purchase invoice puts it to approval (option A), and an entity may ask for the approval before posting.
RSpec.describe Accounting::PostInvoice, "approval" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:invoice) { create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal) }

  def policy!
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
    end
  end

  context "by default" do
    it "puts the invoice to approval when it is posted, and the accounting is not held back" do
      policy!

      expect(described_class.call(invoice: invoice)).to be_success
      expect(invoice.reload).to be_posted
      expect(invoice).to be_payment_to_approve
      expect(Approvals::Request.pending.sole.subject).to eq(invoice)
    end

    it "counts the VAT of an invoice in the VAT return while its approval is still waiting (the deduction does not wait for the approval)" do
      policy!

      described_class.call(invoice: invoice)

      expect(invoice.reload).to be_payment_to_approve
      grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id, period_start: fiscal_year.start_date, period_end: fiscal_year.end_date)
      expect(grids["59"]).to eq(BigDecimal("210.00")) # 21 % of 1,000.00, deductible
    end

    it "records that no approval is needed when no policy applies" do
      described_class.call(invoice: invoice)

      expect(invoice.reload).to be_payment_not_required
      expect(Approvals::Request.count).to eq(0)
    end

    it "does not put a sales invoice to approval" do
      policy!
      sale = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: create(:journal, :sale))

      described_class.call(invoice: sale)

      expect(Approvals::Request.count).to eq(0)
    end

    it "does nothing when the feature is off" do
      policy!
      entity.update!(features: entity.features.merge("b01a" => false))

      expect(described_class.call(invoice: invoice)).to be_success
      expect(Approvals::Request.count).to eq(0)
    end
  end

  context "when the entity asks for the approval before posting" do
    before { entity.update!(bap_before_posting: true) }

    it "refuses to post an invoice a policy applies to and nobody has approved" do
      policy!

      result = described_class.call(invoice: invoice)

      expect(result).to be_failure
      expect(result.message).to match(/approval/i)
      expect(invoice.reload).to be_draft
    end

    it "posts it once it has been approved" do
      policy!
      request = Approvals::Submit.call(invoice: invoice, user: nil)[:request]
      Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint)

      expect(described_class.call(invoice: invoice)).to be_success
      expect(invoice.reload).to be_posted
      expect(invoice).to be_payment_approved
    end

    it "refuses an approval that no longer matches the content" do
      policy!
      request = Approvals::Submit.call(invoice: invoice, user: nil)[:request]
      Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint)
      invoice.lines.first.update!(unit_price: "5000.00")

      expect(described_class.call(invoice: invoice)).to be_failure
    end

    it "posts freely an invoice no policy applies to" do
      expect(described_class.call(invoice: invoice)).to be_success
    end
  end
end

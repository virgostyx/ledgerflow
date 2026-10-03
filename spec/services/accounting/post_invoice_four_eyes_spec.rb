require "rails_helper"

# F01: the four-eyes rule covers invoices as well as manual entries (spec §4): the author of an invoice may not validate it.
RSpec.describe "Four eyes on invoices" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:sale_journal) { create(:journal, :sale) }

  let(:author)   { create(:user) }
  let(:reviewer) { create(:user) }
  let(:invoice)  { create(:invoice, :draft, :with_lines, invoice_type: :customer, journal: sale_journal, fiscal_year: fiscal_year, created_by: author) }

  def post_as(user) = Current.set(user: user) { Accounting::PostInvoice.call(invoice: invoice) }

  context "with the option on and no threshold" do
    before { entity.update!(four_eyes: true) }

    it "refuses the author, and the invoice stays a draft" do
      result = post_as(author)

      expect(result).to be_failure
      expect(result.message).to match(/another person/i)
      expect(invoice.reload).to be_draft
    end

    it "accepts another person" do
      expect(post_as(reviewer)).to be_success
    end

    it "does not block an invoice that has no author (API, Peppol, recurring)" do
      invoice.update_columns(created_by_id: nil)

      expect(post_as(author)).to be_success
    end

    it "does not block a job without a user" do
      expect(Accounting::PostInvoice.call(invoice: invoice)).to be_success
    end
  end

  context "with a threshold" do
    before { entity.update!(four_eyes: true) }

    let(:total) do
      twin = create(:invoice, :draft, :with_lines, invoice_type: :customer, journal: sale_journal, fiscal_year: fiscal_year)
      Accounting::PostInvoice.call(invoice: twin)
      twin.reload.total_incl_vat
    end

    it "applies from the invoice total including VAT, bound included" do
      entity.update!(four_eyes_threshold: total)

      expect(post_as(author)).to be_failure
    end

    it "does not apply below the threshold" do
      entity.update!(four_eyes_threshold: total + 0.01)

      expect(post_as(author)).to be_success
    end
  end

  it "is off by default" do
    expect(post_as(author)).to be_success
  end

  describe "#four_eyes_blocks?" do
    it "is false without user, without author or without the option" do
      expect(invoice.four_eyes_blocks?(nil)).to be false
      expect(invoice.four_eyes_blocks?(author)).to be false # option off

      entity.update!(four_eyes: true)
      invoice.created_by = nil
      expect(invoice.four_eyes_blocks?(author)).to be false
    end
  end
end

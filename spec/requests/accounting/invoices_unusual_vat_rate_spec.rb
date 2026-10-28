require "rails_helper"

# The select of the VAT rate of a line offers the Belgian rates. A rate an application sent (16 % in Zambia) is not one of them: it has to be shown as the
# line's, or the browser picks the first choice (0 %) and saving the line to code it wipes the VAT out.
RSpec.describe "VAT rate of an invoice line the form does not know", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:supplier) { create(:partner, :supplier) }
  let(:invoice) { create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year) }

  before { sign_in accountant }

  def rate_select
    get edit_accounting_invoice_path(invoice)
    response.body[/<select[^>]*data-line-vat-rate[^>]*>.*?<\/select>/m] || response.body[/<select[^>]*line_vat_rate[^>]*>.*?<\/select>/m]
  end

  def line_with(rate) = create(:invoice_line, invoice: invoice, account: account_604, vat_rate: rate)

  it "offers a rate the form does not know, selected, so that saving keeps it" do
    line_with(BigDecimal("16"))

    expect(rate_select).to match(/<option[^>]*selected[^>]*value="16.00"[^>]*>16%<\/option>|<option[^>]*value="16.00"[^>]*selected[^>]*>16%<\/option>/)
  end

  it "shows a rate with decimals as it is" do
    line_with(BigDecimal("12.35"))

    expect(rate_select).to include("12.35%")
  end

  it "keeps the four usual rates and adds nothing for one of them" do
    line_with(BigDecimal("21"))

    expect(rate_select.scan("<option").size).to eq(4)
  end
end

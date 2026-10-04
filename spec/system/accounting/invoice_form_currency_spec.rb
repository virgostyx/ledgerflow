require "rails_helper"

# F11: choosing a foreign currency on an invoice shows the official rate of its date and the EUR equivalent, as one types; another rate asks for its reason.
RSpec.describe "Invoice form in a foreign currency", type: :system, js: true do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:partner) { create(:partner, name: "Acme Ltd", payment_terms_days: 30) }

  def rate = find("#accounting_invoice_exchange_rate").value

  before do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.current, rate: "1.25", rate_type: :daily, source: "ecb")
    login_as accountant, scope: :user
    visit accounting_new_sales_path
    click_button "Refuse" if page.has_button?("Refuse", wait: 1) # the cookie banner is fixed at the bottom of the window
  end

  it "fills in the official rate of the invoice date when a currency is chosen, and EUR is 1" do
    select "USD", from: "accounting_invoice_currency"
    expect(page).to have_field("accounting_invoice_exchange_rate", with: "1.25")

    select "EUR", from: "accounting_invoice_currency"
    expect(page).to have_field("accounting_invoice_exchange_rate", with: "1")
  end

  it "says which rate is missing, naming the currency and the date, rather than keeping another" do
    select "GBP", from: "accounting_invoice_currency"
    expect(page).to have_content("No exchange rate for GBP on #{Accounting::DatePresenter.new(Date.current).format}")
  end

  it "asks for a reason as soon as the rate typed is not the official one, and not before" do
    select "USD", from: "accounting_invoice_currency"
    expect(page).to have_field("accounting_invoice_exchange_rate", with: "1.25")
    expect(page).to have_no_field("accounting_invoice_exchange_rate_reason")

    fill_in "accounting_invoice_exchange_rate", with: "1.30"
    expect(page).to have_field("accounting_invoice_exchange_rate_reason")

    fill_in "accounting_invoice_exchange_rate", with: "1.25"
    expect(page).to have_no_field("accounting_invoice_exchange_rate_reason")
  end

  it "shows the EUR equivalent of the total at that rate" do
    select "USD", from: "accounting_invoice_currency"
    expect(page).to have_field("accounting_invoice_exchange_rate", with: "1.25")
    select "Export", from: "accounting_invoice_vat_treatment" # no VAT: the total is the amount
    find(%(input[name="accounting_invoice[lines_attributes][0][unit_price]"])).set("1000")
    expect(find('[data-invoice-form-target="invoiceTotalEur"]')).to have_content("800,00 EUR")
  end
end

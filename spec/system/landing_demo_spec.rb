require "rails_helper"

# The landing page demo does money maths in the browser (integer cents, VAT rounded half-up); this is its only automated check.
RSpec.describe "Landing page demo", type: :system, js: true do
  def amount(value) = fill_in("Amount excl. VAT (€)", with: value)

  before do
    visit root_path
    page.execute_script("localStorage.setItem('lf_cookie_consent', 'refused')") # no banner sliding over the page
    visit root_path
  end

  it "balances the default sale: 1 000,00 net + 210,00 VAT" do
    expect(page).to have_text(/Debit 1[[:space:]]210,00[[:space:]]€ = Credit 1[[:space:]]210,00[[:space:]]€ ✓ balanced/)
  end

  it "rounds VAT half-up to the cent (0,50 at 21 % is 0,105, so 0,11)" do
    amount("0.50")
    within("[data-ledger-demo-target=sale]") { expect(page).to have_text(/0,11[[:space:]]€/) }
    expect(page).to have_text(/Debit 0,61[[:space:]]€ = Credit 0,61[[:space:]]€ ✓ balanced/)
  end

  it "applies the chosen rate (0,25 at 6 % is 0,015, so 0,02)" do
    choose "6%"
    amount("0.25")
    within("[data-ledger-demo-target=sale]") { expect(page).to have_text(/0,02[[:space:]]€/) }
  end

  it "shows the purchase entry with VAT recoverable and suppliers" do
    choose "Purchase"
    expect(page).to have_text("604000 Purchases of goods")
    expect(page).to have_text("440000 Suppliers")
    expect(page).not_to have_text("700000 Sales")
  end

  it "caps the amount at 999 999 999,99" do
    amount("1e30")
    expect(page).to have_text(/Debit 1[[:space:]]209[[:space:]]999[[:space:]]999,99[[:space:]]€/)
  end

  it "rejects an unbalanced entry on request, and fixes it again" do
    click_button "Try to break it"
    expect(page).to have_text("Rejected by PostgreSQL")
    click_button "Fix it"
    expect(page).to have_text("✓ balanced")
  end
end

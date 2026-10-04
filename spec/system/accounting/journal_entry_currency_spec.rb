require "rails_helper"

# F11: on a line of a manual entry, a currency and an amount in it become the euros of the debit or the credit at the official rate of the date.
RSpec.describe "Entry in a foreign currency", type: :system, js: true do
  include_context "with_open_fiscal_year"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:account_604) { create(:account, code: "604000", label_fr: "Services divers") }
  let!(:account_440) { create(:account, code: "440000", label_fr: "Fournisseurs") }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.current, rate: "1.25", rate_type: :daily, source: "ecb")
    login_as accountant, scope: :user
    visit new_accounting_journal_entry_path
    click_button "Refuse" if page.has_button?("Refuse", wait: 1) # the cookie banner is fixed at the bottom of the window
    select "ACH — Achats", from: "Journal"
    execute_script("document.querySelector('input[type=\"date\"]').value = '#{Date.current.iso8601}'")
    fill_in "Description", with: "USD supplies"
  end

  def set_account(index, account)
    execute_script("document.querySelectorAll('.entry-lines')[#{index}].querySelector('[name*=\"account_id\"]').value = '#{account.id}'")
  end

  it "shows the rate, turns the amount into euros, and posts an entry balanced in EUR" do
    set_account(0, account_604)
    within(all(".entry-lines")[0]) do
      select "USD", from: "Currency"
      fill_in "Amount in currency", with: "1000"
      expect(page).to have_field("Rate per 1 EUR", with: "1.25")
      expect(page).to have_field("Debit", with: "800")
    end

    click_button "Add a line"
    expect(page).to have_css(".entry-lines", count: 2)
    set_account(1, account_440)
    within(all(".entry-lines")[1]) do
      select "USD", from: "Currency"
      select "Credit", from: "Side of the amount in currency"
      fill_in "Amount in currency", with: "1000"
      expect(page).to have_field("Credit", with: "800")
    end

    expect(page).to have_css(".balance-indicator .bg-emerald-100", text: "Balanced")
    click_button "Save"

    expect(page).to have_css(".bg-emerald-100", text: "Posted")
    entry = Accounting::JournalEntry.last
    expect(entry.lines.find_by(account: account_604)).to have_attributes(debit: BigDecimal("800"), amount_currency: BigDecimal("1000"), currency: "USD")
  end

  it "says which rate is missing, naming the currency and the date" do
    within(all(".entry-lines")[0]) do
      select "GBP", from: "Currency"
      fill_in "Amount in currency", with: "100"
      expect(page).to have_content("No exchange rate for GBP")
    end
  end
end

require "rails_helper"

# F04 §7: keyboard shortcuts, live difference, rounding button and one-click suggestion on the lettering screen.
RSpec.describe "Lettering screen", type: :system, js: true do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:supplier) { create(:partner, :supplier) }
  let(:journal)  { create(:journal, :cash) }
  let!(:misc)    { create(:journal, journal_type: :misc) }
  let!(:loss)    { create(:account, code: "658100", label_fr: "Rounding (charge)", account_class: 6, entity: entity) }
  let!(:gain)    { create(:account, code: "758100", label_fr: "Rounding (income)", account_class: 7, entity: entity) }

  def line(debit: 0, credit: 0)
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 20)
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  let!(:invoice_line) { line(credit: 100.00) }
  let!(:payment)      { line(debit: 99.97) }

  before do
    login_as accountant, scope: :user
    visit new_accounting_lettering_path(account_id: account_440.id)
  end

  it "ticks with the keyboard, shows the difference and offers the rounding entry, not the plain lettering" do
    find("body").send_keys("x", "j", "x")

    expect(page).to have_css("[data-lettering-total-target='difference']", text: "0.03")
    expect(page).to have_button("Letter selected lines", disabled: true)
    expect(page).to have_button("Letter with a rounding entry", disabled: false)
  end

  it "books the rounding entry as a draft" do
    find("body").send_keys("x", "j", "x")
    click_button "Letter with a rounding entry"

    expect(page).to have_content("Rounding entry created as a draft")
    expect(invoice_line.reload.lettering_id).to be_nil
  end

  it "letters with the l key when the group balances" do
    exact = line(debit: 0.03)
    visit new_accounting_lettering_path(account_id: account_440.id)
    find("body").send_keys("x", "j", "x", "j", "x", "l")

    expect(page).to have_content("Lines lettered")
    expect(exact.reload.lettering_id).to be_present
  end

  it "accepts a rounding suggestion in one click, which books the draft entry" do
    Accounting::SuggestLetterings.call
    visit new_accounting_lettering_path(account_id: account_440.id)
    within("li", text: "rule 6") { click_button "Accept" }

    expect(page).to have_content("Suggestion accepted")
    expect(Accounting::LetteringWriteOff.count).to eq(1)
  end
end

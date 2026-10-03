require "rails_helper"

# The system journey that closes wave P0 (docs/dev/features/spec.md §17.4): a CODA file is imported, its lines are matched, the
# period is locked, a supporting document is read from the entry; and the invariants hold at the end. Everything goes through the
# screens, as people do, with the roles that have the right to each step.
RSpec.describe "P0 journey: CODA import, matching, locked period, document", type: :system do
  include_context "with_open_fiscal_year"

  let(:month)   { fiscal_year.start_date.beginning_of_month + 1.month }
  let(:day)     { month + 9 }
  let(:acme)    { CodaBuilder.iban("539007547034") }
  let(:accountant) { create(:user, role: :accountant, full_name: "Alice Accountant") }
  let(:assistant)  { create(:user, role: :auditor, full_name: "Bob Assistant") }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }

  let!(:bank_gl)     { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:receivable)  { create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) }
  let!(:capital)     { create(:account, code: "100000", label_fr: "Capital", account_type: :equity, normal_balance: :credit) }
  let!(:fees)        { create(:account, code: "651100", label_fr: "Frais bancaires") }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let!(:misc_journal) { create(:journal, :misc) }
  let!(:bank_account) { create(:bank_account, iban: acme, journal: bank_journal, label_fr: "Compte courant ACME") }
  let(:partner) { create(:partner, name: "DUPONT ET FILS SPRL", iban: CodaBuilder.iban("091012345678")) }
  let!(:invoice) { create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("1210")) } }

  let(:movements) do
    [ { amount: "1210.00", value_date: day, bank_reference: "JRNY0000000000000001", structured: CodaBuilder.structured(invoice.id), counterparty_name: "DUPONT ET FILS SPRL", counterparty_iban: partner.iban },
      { amount: "-12.50", value_date: day, bank_reference: "JRNY0000000000000002", free: "FRAIS DE TENUE DE COMPTE", code: "08002000" },
      { amount: "99.99", value_date: day + 1, bank_reference: "JRNY0000000000000003", free: "SOMETHING NOBODY EXPECTED", counterparty_name: "STRANGER" } ]
  end
  let(:coda) { CodaBuilder.file(statements: [ { iban: acme, sequence: 1, date: day + 2, old_balance: "1000.00", movements: movements } ]) }

  def write(name, content)
    Rails.root.join("tmp/#{name}").tap { |path| File.binwrite(path, content) }
  end

  # The bank opened the account with 1 000,00 and so did the ledger.
  before do
    entry = create(:journal_entry, :draft, journal: misc_journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank_gl, debit: 1000, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: capital, debit: 0, credit: 1000)
    entry.post!
    Accounting::BankRule.create!(name: "Bank fees", condition_type: "contains", condition_value: "frais de tenue", account: fees, score: 85)
  end

  after { Dir[Rails.root.join("tmp/journey_*")].each { |file| File.delete(file) } }

  it "goes from the bank file to a document read from the entry, and the books still balance" do
    login_as accountant, scope: :user

    # 1. The file comes in; a second time it does not; a broken one is refused with its faulty lines.
    visit new_accounting_bank_statement_path
    attach_file "CODA file", write("journey_statement.cod", coda)
    click_button "Import"
    expect(page).to have_content("3 lines imported")
    expect(Accounting::BankTransaction.count).to eq(3)

    visit new_accounting_bank_statement_path
    attach_file "CODA file", write("journey_statement_again.cod", coda)
    click_button "Import"
    expect(page).to have_content("already imported")
    expect(Accounting::BankTransaction.count).to eq(3)

    lines = coda.split("\r\n")
    lines[3] = lines[3][0, 100]
    visit new_accounting_bank_statement_path
    attach_file "CODA file", write("journey_broken.cod", lines.join("\r\n"))
    click_button "Import"
    expect(page).to have_content("line 4")
    expect(Accounting::BankTransaction.count).to eq(3)

    # 2. The engine drafted the exact match; the fee and the unknown line wait.
    visit accounting_bank_reconciliation_path
    expect(page).to have_css("#indicator-imported", text: "3")
    expect(page).to have_css("#indicator-pending", text: "2")
    expect(page).to have_content("Awaiting validation")
    expect(page).to have_content("rule “Bank fees”")
    payment = Accounting::BankTransaction.find_by(bank_reference: "JRNY0000000000000001")
    expect(payment).to be_matched
    expect(payment.journal_entry).to be_draft
    expect(invoice.reload).to be_posted

    # 3. The assistant confirms the fee: a draft only. Nor can the assistant validate the payment.
    login_as assistant, scope: :user
    visit accounting_bank_reconciliation_path
    within(find("tr", text: "FRAIS DE TENUE")) { click_button "Accept" }
    fee = Accounting::BankTransaction.find_by(bank_reference: "JRNY0000000000000002")
    expect(fee).to be_matched
    expect(fee.journal_entry).to be_draft

    visit accounting_journal_entry_path(payment.journal_entry)
    expect(page).not_to have_button("Post")

    # 4. The accountant validates the payment: the line is settled and the invoice paid.
    login_as accountant, scope: :user
    visit accounting_journal_entry_path(payment.journal_entry)
    click_button "Post"
    expect(payment.reload).to be_reconciled
    expect(payment.journal_entry).to be_posted
    expect(invoice.reload).to be_paid

    # 5. The month is locked: nothing more is posted in it, by the service nor behind its back.
    visit accounting_period_locks_path
    check "month_#{month.strftime('%Y_%m')}"
    click_button "Lock the ticked months"
    expect(page).to have_content("1 month locked")

    late = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: day)
    visit accounting_journal_entry_path(late)
    expect(page).to have_content("locked period")
    expect(page).not_to have_button("Post")
    expect(Accounting::PostJournalEntry.call(entry: late)).to be_failure

    # 6. A supporting document is dropped in the inbox, attached to the entry, and read from it.
    visit accounting_documents_path
    attach_file "files", write("journey_receipt.pdf", sample_pdf("receipt"))
    click_button "Upload"
    expect(page).to have_content("journey_receipt.pdf")

    visit accounting_journal_entry_path(payment.journal_entry)
    select "journey_receipt.pdf", from: "document_id"
    click_button "Attach"
    expect(page).to have_link("journey_receipt.pdf")
    click_link "journey_receipt.pdf"
    click_link "Download"
    expect(page.response_headers["Content-Type"]).to include("pdf")

    # 7. The invariants, on what this journey wrote (I1, I2, I3, I5) and the audit chain.
    ActsAsTenant.with_tenant(entity) do
      posted = Accounting::JournalEntry.posted.includes(:lines)
      expect(posted.reject { |e| e.lines.sum(&:debit) == e.lines.sum(&:credit) }).to be_empty # I1

      rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call
      expect(rows.sum { |r| r.total_debit - r.total_credit }).to eq(0) # I2
      rows.each do |row| # I3
        ledger = Accounting::GeneralLedgerQuery.new(account: Accounting::Account.find(row.id), fiscal_year: fiscal_year).call
        expect(ledger.last.running_balance).to eq(row.balance) unless ledger.empty?
      end

      expect(Accounting::BankReconciliationQuery.new(bank_account: bank_account, as_of: day + 2).call.gap).to eq(0) # I5
      expect(Accounting::AuditVerifier.call(entity: entity)).to be_intact
    end

    # The second layer of the lock, last because PostgreSQL's refusal ends the transaction of the example.
    expect { ApplicationRecord.connection.execute("UPDATE accounting_journal_entries SET description = 'x' WHERE id = #{payment.journal_entry_id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /locked period/)
  end
end

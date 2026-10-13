require "rails_helper"

# B01c "spec système de la frise du paiement": the statement of the bank (a CODA file, here the one the specification describes) shows the debit of a batch; the person who
# reconciles the bank confirms it in one click; another one validates the payments; the invoices are paid and lettered, and the timeline of the batch and of an invoice says so.
RSpec.describe "From the debit on the statement to the invoice lettered", type: :system do
  include_context "with submitted batch"

  let(:poster) { create(:user, full_name: "Paula Poster").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:beta) { create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago) } }
  let(:acme_invoice) { posted(unit_price: 1000) }
  let(:beta_invoice) { posted(partner: beta, unit_price: 500) }
  let(:batch) { submitted_batch(acme_invoice, beta_invoice) }

  def import_statement!(movements)
    bytes = CodaBuilder.file(statements: [ { iban: bank.iban, movements: movements } ])
    Banking::ImportStatements.call(bytes: bytes, user: exporter, source_name: "statement.cod").tap { |r| raise "#{r[:reason]}: #{r[:errors]}" if r.failure? }
  end

  before do
    bank.update_columns(iban: CodaBuilder.iban("539007547034"))
    owner
  end

  it "takes the grouped debit of the batch, then the validation, to invoices paid and lettered, with the timeline to show for it" do
    import_statement!([ { amount: "-1815.00", entry_date: execution, value_date: execution, free: "#{batch.reference} 2 PAYMENTS", counterparty_name: "LEDGER FLOW SRL" } ])
    login_as exporter, scope: :user

    visit accounting_bank_reconciliation_path
    expect(page).to have_content(/debit of payment batch #{batch.reference} \(2 payments, 1\D815,00/).and have_content("score 100")
    click_button "Accept", match: :first # the first one is the suggestion (the other is the cookie banner)

    expect(batch.reload).to be_debited
    visit accounting_payment_path(batch)
    expect(page).to have_content("One draft entry was made for each payment")
    expect(page).to have_content("Debited")

    login_as poster, scope: :user
    visit accounting_payment_path(batch)
    click_button "Validate the payments of the batch"
    expect(page).to have_content("The payments were validated and lettered")
    expect(page).to have_content("Payments validated").and have_content("Paula Poster")

    expect([ acme_invoice, beta_invoice ].map { |i| i.reload.status }).to all(eq("paid"))
    expect(Accounting::BankTransaction.find(batch.items.first.bank_transaction_id)).to be_reconciled
    visit accounting_invoice_path(acme_invoice)
    expect(page).to have_content("Payment timeline").and have_content("Lettered")
  end

  it "takes the lines of the payments one by one when the bank lists them so, each with its end-to-end id" do
    acme = batch.items.find_by(holder_name: "Acme Ltd")
    beta_item = batch.items.find_by(holder_name: "Beta Corp")
    import_statement!([ { amount: "-1210.00", entry_date: execution, value_date: execution, customer_reference: acme.end_to_end_id, counterparty_iban: "BE68539007547034", counterparty_name: "ACME LTD" },
                        { amount: "-605.00", entry_date: execution, value_date: execution, customer_reference: beta_item.end_to_end_id, counterparty_iban: "BE71096123456769", counterparty_name: "BETA CORP" } ])
    login_as exporter, scope: :user

    visit accounting_bank_reconciliation_path
    expect(page).to have_content("score 100", count: 2)
    2.times do
      visit accounting_bank_reconciliation_path
      click_button "Accept", match: :first
    end

    expect(batch.reload).to be_debited
    expect(batch.items.map(&:status).uniq).to eq([ "confirmed" ])
    expect(batch.items.map(&:bank_transaction_id).uniq.size).to eq(2)
  end
end

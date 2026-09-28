require "rails_helper"

# R09 panneau de cohérence — invariant I7 (docs/dev/reports/spec.md §2.3, §10): the VAT
# return's balance (grid 71/72) must equal the movement of 451 (VAT payable) minus 411
# (VAT recoverable) over the period, apart from entries that carry no VAT grid (payments,
# manual regularizations), which are listed as the explained part.
RSpec.describe Accounting::VatConsistencyQuery, type: :query do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:sale_journal)     { create(:journal, :sale) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:customer) { create(:partner, name: "Cust", vat_number: "BE0200000043", country: "BE") }
  let(:supplier) { create(:partner, :supplier, name: "Supp", vat_number: "BE0403170701", country: "BE") }
  let(:period)   { [ fiscal_year.start_date, fiscal_year.end_date ] }

  def invoice(type, amount, account:, rate: 21, treatment: :domestic, credit_note: false)
    inv = create(:invoice, invoice_type: type, partner: type == :customer ? customer : supplier, fiscal_year: fiscal_year,
                 invoice_date: fiscal_year.start_date + 10, vat_treatment: treatment, status: :draft,
                 document_type: credit_note ? :credit_note : :invoice)
    create(:invoice_line, invoice: inv, account: account, unit_price: amount, quantity: 1, vat_rate: rate)
    result = Accounting::PostInvoice.call(invoice: inv)
    raise result.message if result.failure?
    inv
  end

  def result
    grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id, period_start: period[0], period_end: period[1])
    declared = Accounting::VatGrid.balance(grids.transform_values { |v| v })
    declaration = build(:vat_declaration, fiscal_year: fiscal_year, period_start: period[0], period_end: period[1],
                        grids: grids.merge(declared).transform_values { |v| format("%.2f", v) })
    described_class.new(declaration: declaration).call
  end

  it "balances on domestic sales and purchases" do
    invoice(:customer, 1000, account: account_700) # VAT due 210
    invoice(:supplier, 400, account: account_604)   # VAT deductible 84
    expect(result).to have_attributes(declared_balance: 126, gridded_net: 126, residual: 0)
  end

  it "balances with reverse charge, credit notes and a non-deductible share" do
    invoice(:supplier, 500, account: account_604, treatment: :intracom_goods)
    invoice(:customer, 300, account: account_700, credit_note: true)
    invoice(:supplier, 100, account: account_604, credit_note: true)
    expect(result.residual).to eq(0)
  end

  it "keeps a VAT payment (no grid) out of the gridded figures and lists it as explained" do
    invoice(:customer, 1000, account: account_700)
    entry = create(:journal_entry, :draft, journal: create(:journal, :misc), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 20)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_451, debit: 210, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_550, debit: 0, credit: 210)
    entry.post!

    expect(result).to have_attributes(ledger_net: 0, ungridded_net: -210, residual: 0)
  end
end

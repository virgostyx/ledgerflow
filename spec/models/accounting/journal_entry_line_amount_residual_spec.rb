require "rails_helper"

# docs/dev/reports/spec.md §7: amount_residual is maintained by the lettering
# service (not a DB trigger), because it depends on accounting_line_allocations
# and accounting_letterings — both changed via update_all/nullify, which bypass
# AR callbacks. See Accounting::JournalEntryLine.resync_amount_residual!.
RSpec.describe "amount_residual maintenance", type: :model do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:supplier) { create(:partner, :supplier) }
  let(:journal)  { create(:journal, :cash) }

  def line(debit: 0, credit: 0, partner: supplier, account: account_440, invoice: nil)
    entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account, partner: partner, invoice: invoice,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
  end

  def invoice_line(amount)
    credit_line = line(credit: amount)
    invoice = create(:invoice, :posted, :supplier, fiscal_year: fiscal_year, partner: supplier,
                     journal_entry: credit_line.journal_entry)
    credit_line.update_columns(invoice_id: invoice.id)
    credit_line
  end

  it "defaults to its own amount on a new, untouched line" do
    expect(line(debit: 100).amount_residual).to eq(BigDecimal("100"))
    expect(line(credit: 250).amount_residual).to eq(BigDecimal("250"))
  end

  it "is reduced on both lines by a partial allocation" do
    credit_line = invoice_line(1000)
    payment     = line(debit: 600)

    Accounting::AllocateLines.call(lines: [ credit_line, payment ])

    expect(credit_line.reload.amount_residual).to eq(BigDecimal("400"))
    expect(payment.reload.amount_residual).to eq(0)
  end

  it "is zeroed on every line once a group is lettered" do
    credit_line = line(credit: 121)
    debit_line  = line(debit: 121)

    Accounting::LetterLines.call(lines: [ credit_line, debit_line ])

    expect(credit_line.reload.amount_residual).to eq(0)
    expect(debit_line.reload.amount_residual).to eq(0)
  end

  it "is restored when the lettering is undone" do
    credit_line = line(credit: 121)
    debit_line  = line(debit: 121)
    lettering = Accounting::LetterLines.call(lines: [ credit_line, debit_line ]).lettering

    Accounting::UnletterLines.call(lettering: lettering)

    expect(credit_line.reload.amount_residual).to eq(BigDecimal("121"))
    expect(debit_line.reload.amount_residual).to eq(BigDecimal("121"))
  end

  it "is restored on both lines when a partial allocation is removed" do
    credit_line = invoice_line(1000)
    payment     = line(debit: 600)
    Accounting::AllocateLines.call(lines: [ credit_line, payment ])
    allocation = Accounting::LineAllocation.first

    Accounting::RemoveAllocation.call(allocation: allocation)

    expect(credit_line.reload.amount_residual).to eq(BigDecimal("1000"))
    expect(payment.reload.amount_residual).to eq(BigDecimal("600"))
  end
end

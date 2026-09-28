# R09 panneau de cohérence — invariant I7 (docs/dev/reports/spec.md §2.3, §10): compares the
# VAT return's balance (grid 71 positive = due, grid 72 negative = to recover) with what the
# ledger says for the period: movement of 450100 (VAT payable, "451") minus 410100 (VAT
# recoverable, "411"). Lines that carry no VAT grid (payments to the State, manual
# regularizations) are moved out of the comparison and reported as `ungridded_net`, the
# explained part; `residual` is what stays unexplained and must be zero.
class Accounting::VatConsistencyQuery
  Result = Struct.new(:declared_balance, :ledger_net, :ungridded_net, :gridded_net, :residual, :anomalies,
                      keyword_init: true)
  Anomaly = Struct.new(:invoice_id, :invoice_number, :expected_vat, :booked_vat, keyword_init: true)

  TOLERANCE = BigDecimal("0.05") # per document, spec §10

  def initialize(declaration:)
    @declaration = declaration
  end

  def call
    ledger   = net_position(lines)
    ungrided = net_position(lines.where(vat_code: nil))
    declared = @declaration.grid_total("71") - @declaration.grid_total("72")

    Result.new(declared_balance: declared, ledger_net: ledger, ungridded_net: ungrided, gridded_net: ledger - ungrided,
               residual: (ledger - ungrided) - declared, anomalies: rate_anomalies)
  end

  private

  def lines
    Accounting::JournalEntryLine.joins(:journal_entry, :account)
      .where(accounting_journal_entries: { fiscal_year_id: @declaration.fiscal_year_id,
                                           status: Accounting::JournalEntry.statuses[:posted],
                                           entry_date: @declaration.period_start..@declaration.period_end })
  end

  # VAT payable's credit balance minus VAT recoverable's debit balance: positive = owed to the State.
  def net_position(scope)
    payable     = scope.where(accounting_accounts: { code: Accounting::AccountCodes::VAT_PAYABLE })
    recoverable = scope.where(accounting_accounts: { code: Accounting::AccountCodes::VAT_DEDUCTIBLE })
    (payable.sum(:credit) - payable.sum(:debit)) - (recoverable.sum(:debit) - recoverable.sum(:credit))
  end

  # base x rate ≈ VAT, per document (spec §10); listed, never blocking.
  def rate_anomalies
    Accounting::Invoice.where(fiscal_year_id: @declaration.fiscal_year_id, status: %w[posted paid partially_paid],
                              invoice_date: @declaration.period_start..@declaration.period_end)
      .includes(:lines).filter_map do |invoice|
        expected = invoice.lines.sum(BigDecimal("0")) { |l| (l.subtotal_excl_vat * l.vat_rate / 100).round(2) }
        next if (expected - invoice.vat_amount).abs <= TOLERANCE

        Anomaly.new(invoice_id: invoice.id, invoice_number: invoice.invoice_number, expected_vat: expected,
                    booked_vat: invoice.vat_amount)
      end
  end
end

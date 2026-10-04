class Accounting::GeneralLedgerQuery
  Result = Struct.new(:line_id, :entry_date, :reference, :label,
                      :debit, :credit, :running_balance, :journal_entry_id,
                      :partner_id, :partner_name, :lettering_code, :lettering_id,
                      :currency, :amount_currency, :exchange_rate,
                      keyword_init: true)

  attr_reader :opening_balance

  # partner/journal: narrows to one (grand livre auxiliaire d'un tiers / d'un journal).
  # lettering: nil (tous), :lettered ou :unlettered.
  def initialize(account:, fiscal_year:, date_from: nil, date_to: nil, partner: nil, journal: nil, lettering: nil)
    @account     = account
    @fiscal_year = fiscal_year
    @date_from   = date_from || fiscal_year.start_date
    @date_to     = date_to   || fiscal_year.end_date
    @partner     = partner
    @journal     = journal
    @lettering   = lettering
    @opening_balance = BigDecimal("0")
  end

  def call
    @opening_balance = compute_opening_balance

    lines = base_scope
      .where(
        "accounting_journal_entries.entry_date BETWEEN ? AND ?",
        @date_from, @date_to
      )
      .order(
        "accounting_journal_entries.entry_date ASC",
        "accounting_journal_entry_lines.id ASC"
      )

    running = @opening_balance
    lines.map do |line|
      running += signed_delta(line)

      Result.new(
        line_id:          line.id,
        entry_date:       line.journal_entry.entry_date,
        reference:        line.journal_entry.reference,
        label:            line.label,
        debit:            line.debit,
        credit:           line.credit,
        running_balance:  running,
        journal_entry_id: line.journal_entry_id,
        partner_id:       line.partner_id,
        partner_name:     line.partner&.name,
        lettering_code:   line.lettering&.code,
        lettering_id:     line.lettering_id,
        currency:         line.currency,
        amount_currency:  line.amount_currency,
        exchange_rate:    line.exchange_rate
      )
    end
  end

  private

  def compute_opening_balance
    prior = base_scope.where("accounting_journal_entries.entry_date < ?", @date_from)
                       .pick(Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.debit), 0)"),
                             Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.credit), 0)"))
    debit, credit = prior.map { |v| BigDecimal(v.to_s) }
    @account.normal_balance == "debit" ? debit - credit : credit - debit
  end

  def signed_delta(line)
    @account.normal_balance == "debit" ? line.debit - line.credit : line.credit - line.debit
  end

  def base_scope
    scope = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .includes(:journal_entry, :partner, :lettering)
      .where(account: @account)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.ledger_status_values
        }
      )
    scope = scope.where(partner: @partner) if @partner
    scope = scope.where(accounting_journal_entries: { journal_id: @journal.id }) if @journal
    case @lettering
    when :lettered   then scope = scope.where.not(lettering_id: nil)
    when :unlettered then scope = scope.where(lettering_id: nil)
    end
    scope
  end
end

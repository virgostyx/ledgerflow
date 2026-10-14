class Accounting::GeneralLedgerQuery
  Result = Struct.new(:line_id, :entry_date, :reference, :label,
                      :debit, :credit, :running_balance, :journal_entry_id,
                      :partner_id, :partner_name, :lettering_code, :lettering_id,
                      :currency, :amount_currency, :exchange_rate,
                      keyword_init: true)

  attr_reader :opening_balance

  # partner/journal: narrows to one (grand livre auxiliaire d'un tiers / d'un journal).
  # lettering: nil (tous), :lettered ou :unlettered.
  # known_at (B03a): the ledger as it was known at that instant (a Time or an Accounting::KnownAt): the lines validated by then, the lettering and the partner names that held.
  def initialize(account:, fiscal_year:, date_from: nil, date_to: nil, partner: nil, journal: nil, lettering: nil, known_at: nil)
    @known_at    = Accounting::KnownAt.wrap(known_at, fiscal_year: fiscal_year).ensure_viewable!
    @account     = account
    @fiscal_year = fiscal_year
    @date_from   = date_from || fiscal_year.start_date
    @date_to     = date_to   || fiscal_year.end_date
    @partner     = partner
    @journal     = journal
    @lettering   = lettering
    @opening_balance = BigDecimal("0")
  end

  # How many lines the period holds, and what they add up to (debit, credit): in SQL, for the callers that must not load the lines to know (the agent's ledger tool).
  def line_count = in_period.count

  def totals
    debit, credit = in_period.pick(Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.debit), 0)"), Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.credit), 0)"))
    [ BigDecimal(debit.to_s), BigDecimal(credit.to_s) ]
  end

  def call
    rows, @opening_balance = @known_at.cache(self.class.name, cache_parts) { [ compute_rows, @opening_balance ] }
    rows
  end

  def compute_rows
    @opening_balance = compute_opening_balance

    lines = in_period
      .order(
        "accounting_journal_entries.entry_date ASC",
        "accounting_journal_entry_lines.id ASC"
      )

    running = @opening_balance
    lines = lines.to_a
    as_known = as_known_for(lines)
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
        partner_name:     as_known[:partners].dig(line.partner_id, "name") || line.partner&.name,
        lettering_code:   @known_at.current? ? line.lettering&.code : as_known[:codes][line.id],
        lettering_id:     (line.lettering_id if @known_at.current?),
        currency:         line.currency,
        amount_currency:  line.amount_currency,
        exchange_rate:    line.exchange_rate
      )
    end
  end

  private

  def cache_parts
    { account: @account.id, year: @fiscal_year.id, from: @date_from, to: @date_to, partner: @partner&.id, journal: @journal&.id, lettering: @lettering }
  end

  # What held at the instant (B03a): the name of each partner, and the code of the lettering of each line.
  def as_known_for(lines)
    return { partners: {}, codes: {} } if @known_at.current?

    events = Accounting::LetteringEvent.where(line_id: lines.map(&:id), created_at: ..@known_at.time).order(:line_id, id: :desc).select("DISTINCT ON (line_id) line_id, action, code")
    { partners: Accounting::MasterData.at(Accounting::Partner, lines.filter_map(&:partner_id).uniq, @known_at.time),
      codes: events.select { |event| event.action == "letter" }.to_h { |event| [ event.line_id, event.code ] } }
  end

  def in_period = base_scope.where("accounting_journal_entries.entry_date BETWEEN ? AND ?", @date_from, @date_to)

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
    scope = @known_at.restrict(Accounting::JournalEntryLine.joins(:journal_entry))
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
    lettered = @known_at.current? ? "accounting_journal_entry_lines.lettering_id IS NOT NULL" : "#{Accounting::OpenLineSql.lettered_on_at(@known_at.time)} IS NOT NULL"
    case @lettering
    when :lettered   then scope = scope.where(lettered)
    when :unlettered then scope = scope.where("NOT (#{lettered})")
    end
    scope
  end
end

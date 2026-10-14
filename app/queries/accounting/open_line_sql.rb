# Shared SQL fragments for "is this client/supplier line still open as of a date"
# (docs/dev/reports/spec.md §7), used by AgedBalanceQuery, StaleCreditsQuery and
# UnletteredLinesQuery so they can never disagree (critère d'acceptation #4 : le
# sous-total tiers de R05 doit égaler le total du tiers dans R04).
#
# Callers must join accounting_journal_entries AS e, accounting_accounts AS a,
# LEFT JOIN accounting_partners AS p, LEFT JOIN accounting_invoices AS i,
# LEFT JOIN accounting_letterings AS lt (on l.lettering_id = lt.id).
module Accounting::OpenLineSql
  PREFIX = { customer: "40%", supplier: "44%" }.freeze
  LINES = "accounting_journal_entry_lines".freeze

  # Residual amount, signed like the line, 0 once closed by a lettering dated on/before
  # `as_of` — only allocations dated on/before `as_of` reduce it otherwise.
  # known_at (B03a, an Accounting::KnownAt): the lettering and the allocations as they stood at that instant, rebuilt from the history of the lines and of the allocations
  # (what was lettered or settled later does not count, what was undone since still does).
  def self.residual(kind:, as_of:, known_at: nil)
    net  = kind.to_sym == :customer ? "#{LINES}.debit - #{LINES}.credit" : "#{LINES}.credit - #{LINES}.debit"
    return residual_at(net, as_of, known_at.time) if known_at && !known_at.current?

    used = "COALESCE((SELECT SUM(al.amount) FROM accounting_line_allocations al " \
           "WHERE (al.debit_line_id = #{LINES}.id OR al.credit_line_id = #{LINES}.id) " \
           "AND al.allocated_on <= #{quote(as_of)}), 0)"
    "CASE WHEN #{LINES}.lettering_id IS NOT NULL AND lt.lettered_on <= #{quote(as_of)} THEN 0 " \
    "ELSE (#{net}) - SIGN(#{net}) * #{used} END"
  end

  # The date of the lettering that held the line at `at` (nil: not lettered then): the last event of the line up to that instant, when it lettered.
  def self.lettered_on_at(at)
    "(SELECT ev.lettered_on FROM (SELECT action, lettered_on FROM accounting_lettering_events WHERE line_id = #{LINES}.id AND created_at <= #{quote(at)} " \
    "ORDER BY id DESC LIMIT 1) ev WHERE ev.action = 'letter')"
  end

  def self.residual_at(net, as_of, at)
    used = "COALESCE((SELECT SUM(v.amount) FROM accounting_allocation_versions v " \
           "WHERE (v.debit_line_id = #{LINES}.id OR v.credit_line_id = #{LINES}.id) AND v.action = 'add' AND v.at <= #{quote(at)} AND v.allocated_on <= #{quote(as_of)} " \
           "AND NOT EXISTS (SELECT 1 FROM accounting_allocation_versions r WHERE r.allocation_id = v.allocation_id AND r.action = 'remove' AND r.id > v.id AND r.at <= #{quote(at)})), 0)"
    "CASE WHEN #{lettered_on_at(at)} <= #{quote(as_of)} THEN 0 ELSE (#{net}) - SIGN(#{net}) * #{used} END"
  end

  # The due date a carried line kept (F10), else the invoice's, else the entry date plus the partner's payment terms, else the entry date alone.
  def self.due_date
    "COALESCE(#{LINES}.due_date, i.due_date, (e.entry_date + COALESCE(p.payment_terms_days, 0) * INTERVAL '1 day')::date)"
  end

  # Open-item scope (partner, invoice, lettering joined as documented above) for `kind` as of `as_of`.
  def self.open_scope(kind:, as_of:, known_at: nil)
    scope = Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = #{LINES}.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = #{LINES}.account_id")
      .joins("LEFT JOIN accounting_partners p ON p.id = #{LINES}.partner_id")
      .joins("LEFT JOIN accounting_invoices i ON i.id = #{LINES}.invoice_id")
      .joins("LEFT JOIN accounting_letterings lt ON lt.id = #{LINES}.lettering_id")
      .where("e.status IN (?) AND e.entry_date <= ?", Accounting::JournalEntry.ledger_status_values, as_of)
      .where("a.code LIKE ? AND a.reconcilable", PREFIX.fetch(kind.to_sym))
      .where(carried_forward_sql(as_of, known_at: known_at))
    known_at ? known_at.restrict(scope, table: "e") : scope
  end

  # A line that the next fiscal year carries (a line of a posted entry dated up to `as_of` names it as its origin) is replaced by that line: it is not open
  # any more, the carried one is (F10). Before the carried line's date, the original still is; once the opening entry is reversed (a recalculation), it is again.
  def self.carried_forward_sql(as_of, known_at: nil)
    known = known_at && !known_at.current? ? " AND ce.posted_seq <= #{known_at.seq.to_i}" : ""
    "NOT EXISTS (SELECT 1 FROM #{LINES} carried JOIN accounting_journal_entries ce ON ce.id = carried.journal_entry_id " \
      "WHERE carried.origin_line_id = #{LINES}.id AND ce.status = #{Accounting::JournalEntry.statuses[:posted]} AND ce.entry_date <= #{quote(as_of)}#{known})"
  end

  def self.quote(value) = ApplicationRecord.connection.quote(value)
end

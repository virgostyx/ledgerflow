# R05 (docs/dev/reports/spec.md §7): open (unlettered, at `as_of`) lines on lettrable
# client/supplier accounts, one row per line. Reconstruction shared with
# AgedBalanceQuery via Accounting::OpenLineSql, so subtotals per partner always match
# R04's total for that partner (critère d'acceptation #4).
class Accounting::UnletteredLinesQuery
  Row = Struct.new(:line_id, :account_id, :account_code, :partner_id, :partner_name, :entry_date, :journal_code,
                    :reference, :due_date, :debit, :credit, :residual, :age_days, :lettering_code, :journal_entry_id, keyword_init: true)
  Group = Struct.new(:partner_id, :partner_name, :account_id, :account_code, :lines, keyword_init: true)

  def initialize(kind:, as_of: Date.current, min_age_days: nil)
    @kind         = kind.to_sym
    @as_of        = as_of
    @min_age_days = min_age_days
  end

  def call
    kinds.flat_map { |k| rows_for(k) }.sort_by { |r| [ r.partner_name.to_s, r.entry_date ] }
  end

  # Tiers dont les lignes ouvertes se soldent à zéro sans être lettrées — candidats à
  # un lettrage immédiat (docs/dev/reports/spec.md §7, "Groupes équilibrés non lettrés").
  def balanced_unlettered_groups
    call.group_by { |r| [ r.partner_id, r.account_id ] }
      .filter_map do |(partner_id, account_id), lines|
        next unless lines.size > 1 && lines.sum(&:residual).zero?

        Group.new(partner_id: partner_id, partner_name: lines.first.partner_name,
                   account_id: account_id, account_code: lines.first.account_code, lines: lines)
      end
  end

  private

  def kinds = @kind == :both ? %i[customer supplier] : [ @kind ]

  def rows_for(kind)
    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = accounting_journal_entry_lines.journal_entry_id")
      .joins("JOIN accounting_journals j ON j.id = e.journal_id")
      .joins("JOIN accounting_accounts a ON a.id = accounting_journal_entry_lines.account_id")
      .joins("LEFT JOIN accounting_partners p ON p.id = accounting_journal_entry_lines.partner_id")
      .joins("LEFT JOIN accounting_invoices i ON i.id = accounting_journal_entry_lines.invoice_id")
      .joins("LEFT JOIN accounting_letterings lt ON lt.id = accounting_journal_entry_lines.lettering_id")
      .where("e.status IN (?) AND e.entry_date <= ?", Accounting::JournalEntry.ledger_status_values, @as_of)
      .where("a.code LIKE ? AND a.reconcilable", Accounting::OpenLineSql::PREFIX.fetch(kind))
      .where(Accounting::OpenLineSql.carried_forward_sql(@as_of))
      .pluck(
        Arel.sql("accounting_journal_entry_lines.id"), Arel.sql("a.id"), Arel.sql("a.code"),
        Arel.sql("p.id"), Arel.sql("p.name"), Arel.sql("e.entry_date"), Arel.sql("j.code"),
        Arel.sql("e.reference"), Arel.sql(Accounting::OpenLineSql.due_date),
        Arel.sql("accounting_journal_entry_lines.debit"), Arel.sql("accounting_journal_entry_lines.credit"),
        Arel.sql("(#{Accounting::OpenLineSql.residual(kind: kind, as_of: @as_of)})"),
        Arel.sql("lt.code"), Arel.sql("e.id")
      )
      .filter_map do |line_id, account_id, account_code, partner_id, partner_name, entry_date, journal_code,
                       reference, due_date, debit, credit, residual, lettering_code, journal_entry_id|
        next if residual.zero?
        next if @min_age_days && (@as_of - due_date).to_i < @min_age_days

        Row.new(line_id: line_id, account_id: account_id, account_code: account_code, partner_id: partner_id,
                partner_name: partner_name, entry_date: entry_date, journal_code: journal_code, reference: reference,
                due_date: due_date, debit: debit, credit: credit, residual: residual,
                age_days: (@as_of - due_date).to_i, lettering_code: lettering_code, journal_entry_id: journal_entry_id)
      end
  end
end

# What changed between two periods on the accounts that start with a code, and who explains it (A08): for each account, partner or calendar month, the net movement (debit - credit) in each period, the
# change, and the largest single line of the second period. Everything is summed in SQL over the validated lines; the caller reads a ranked list, never the lines.
class Accounting::VariationQuery
  GROUPS = {
    "account" => { key: "accounting_accounts.code", label: "accounting_accounts.label_fr" },
    "partner" => { key: "COALESCE(posted_lines.partner_id::text, '')", label: "COALESCE(accounting_partners.name, '')" },
    "month"   => { key: "to_char(posted_lines.entry_date, 'MM')", label: "to_char(posted_lines.entry_date, 'MM')" }
  }.freeze

  Row = Struct.new(:key, :label, :first, :second, :change, :largest_line, keyword_init: true)
  Result = Struct.new(:rows, :first_total, :second_total, :change_total, :others_change, :groups, keyword_init: true)

  # `first` and `second` are date ranges. `limit`: how many groups to list, the biggest changes first; the rest is summed in `others_change`.
  def initialize(account_prefix:, first:, second:, group_by: "account", limit: 10)
    raise ArgumentError, "unknown grouping #{group_by}" unless GROUPS.key?(group_by)

    @prefix, @first, @second, @group_by, @limit = account_prefix.to_s, first, second, group_by, limit
  end

  def call
    group = GROUPS.fetch(@group_by)
    rows = scope.group(Arel.sql(group[:key]), Arel.sql(group[:label]))
                .pluck(Arel.sql(group[:key]), Arel.sql(group[:label]), Arel.sql(sum_in(@first)), Arel.sql(sum_in(@second)), Arel.sql(largest_in(@second)))
                .map { |key, label, first, second, largest| build(key, label, first, second, largest) }
    ranked = rows.sort_by { |row| [ -row.change.abs, row.key ] }
    first_total, second_total = scope.pick(Arel.sql(sum_in(@first)), Arel.sql(sum_in(@second))).map { |value| BigDecimal(value.to_s) }
    listed = ranked.first(@limit)
    Result.new(rows: listed, first_total: first_total, second_total: second_total, change_total: second_total - first_total, others_change: ranked.drop(@limit).sum(&:change), groups: rows.size)
  end

  private

  def scope
    Accounting::PostedLine.joins(:account).left_joins(:partner)
      .where("accounting_accounts.code LIKE ?", "#{@prefix.gsub(/[^0-9]/, '')}%")
      .where("posted_lines.entry_date BETWEEN ? AND ? OR posted_lines.entry_date BETWEEN ? AND ?", @first.begin, @first.end, @second.begin, @second.end)
  end

  def build(key, label, first, second, largest)
    first, second = BigDecimal(first.to_s), BigDecimal(second.to_s)
    Row.new(key: key, label: label, first: first, second: second, change: second - first, largest_line: BigDecimal(largest.to_s))
  end

  def sum_in(range) = "COALESCE(SUM(CASE WHEN #{between(range)} THEN posted_lines.debit - posted_lines.credit END), 0)"

  def largest_in(range) = "COALESCE(MAX(CASE WHEN #{between(range)} THEN ABS(posted_lines.debit - posted_lines.credit) END), 0)"

  def between(range) = "posted_lines.entry_date BETWEEN #{ActiveRecord::Base.connection.quote(range.begin)} AND #{ActiveRecord::Base.connection.quote(range.end)}"
end

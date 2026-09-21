class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Building blocks for the `filter_by` scopes of the list pages. Blank input is ignored.
  def self.search(term, *columns)
    return all if term.blank?
    where(columns.map { |c| "#{c}::text ILIKE :t" }.join(" OR "), t: "%#{sanitize_sql_like(term.strip)}%")
  end

  def self.between(column, from, to)
    rel = all
    rel = rel.where(column => from..) if from.present?
    rel = rel.where(column => ..to) if to.present?
    rel
  end

  def self.matching(attrs)
    where(attrs.compact_blank)
  end

  # Per-column filter/sort (AutoFilter style). Only declared columns are reachable from params.
  #   autofilter_column :partner, sql: "accounting_partners.name", type: :string, joins: :partner
  # types: :string (list of values), :enum (keys of the enum named like the column),
  #        :boolean (Active/Inactive),
  #        :date and :decimal (ranges). `filter: false` makes a sort-only column.
  AUTOFILTER_VALUES_LIMIT = 100

  class_attribute :autofilter_columns, default: {}

  def self.autofilter_column(key, sql:, type:, joins: nil, left_joins: nil, filter: true)
    self.autofilter_columns = autofilter_columns.merge(
      key.to_s => { sql: sql, type: type, joins: joins, left_joins: left_joins, filter: filter }
    )
  end

  def self.autofilter(sort: nil, dir: nil, f: {}, except: nil)
    rel = all
    (f || {}).each do |key, value|
      next if key.to_s == except.to_s
      col = autofilter_columns[key.to_s]
      rel = rel.autofilter_apply(col, value) if col && col[:filter]
    end
    col = autofilter_columns[sort.to_s]
    return rel unless col
    rel.autofilter_join(col).reorder(Arel.sql("#{col[:sql]} #{dir.to_s.casecmp?('desc') ? 'DESC' : 'ASC'}"))
  end

  # Distinct values of a string column under the other filters, for the value checklist.
  def self.autofilter_values(key, f: {})
    col = autofilter_columns[key.to_s]
    return [] unless col && col[:type] == :string && col[:filter]
    autofilter(f: f, except: key).autofilter_join(col).reorder(nil)
      .distinct.order(Arel.sql(col[:sql])).limit(AUTOFILTER_VALUES_LIMIT).pluck(Arel.sql(col[:sql])).compact_blank
  end

  def self.autofilter_join(col)
    rel = all
    rel = rel.joins(col[:joins]) if col[:joins]
    rel = rel.left_joins(col[:left_joins]) if col[:left_joins]
    rel
  end

  def self.autofilter_apply(col, value)
    rel = autofilter_join(col)
    sql = col[:sql]
    case col[:type]
    when :string
      values = Array(value).compact_blank
      values.empty? ? rel : rel.where("#{sql} IN (?)", values)
    when :enum
      mapping = defined_enums.fetch(sql.split(".").last)
      values = Array(value).compact_blank
      values.empty? ? rel : rel.where("#{sql} IN (?)", values.filter_map { |v| mapping[v] }.presence || [ nil ])
    when :boolean
      keys = Array(value).compact_blank
      keys.empty? ? rel : rel.where("#{sql} IN (?)", keys.map { |v| { "true" => true, "false" => false }.fetch(v, :none) }.reject { |v| v == :none }.presence || [ nil ])
    when :date
      autofilter_range(rel, sql, value) { |v| Date.iso8601(v) }
    when :decimal
      autofilter_range(rel, sql, value) { |v| BigDecimal(v) }
    else rel
    end
  end

  def self.autofilter_range(rel, sql, value)
    return rel unless value.respond_to?(:key?)
    lo = value["from"].presence || value["min"].presence
    hi = value["to"].presence || value["max"].presence
    rel = rel.where("#{sql} >= ?", yield(lo)) if lo
    rel = rel.where("#{sql} <= ?", yield(hi)) if hi
    rel
  rescue ArgumentError, Date::Error
    rel
  end
end

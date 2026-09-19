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
end

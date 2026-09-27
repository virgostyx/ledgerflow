# Common report filters (docs/dev/reports/spec.md §2.1): fiscal year, date
# range, accounts, journals, partner, draft inclusion, comparative period.
# Entity/company scoping isn't a filter attribute here — every query is
# already scoped to ActsAsTenant.current_tenant, per this app's convention.
class Reports::Filters
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :fiscal_year_id, :integer
  attribute :date_from, :date
  attribute :date_to, :date
  attribute :account_from, :string
  attribute :account_to, :string
  attribute :journal_ids, default: -> { [] }
  attribute :partner_id, :integer
  attribute :include_drafts, :boolean, default: false
  attribute :comparative, :string

  validate :date_from_before_date_to

  def self.from_query(query_string)
    new(Rack::Utils.parse_nested_query(query_string))
  end

  def to_query
    attributes.compact_blank.to_query
  end

  def as_json(*)
    attributes.as_json
  end

  private

  def date_from_before_date_to
    return unless date_from && date_to
    return if date_from <= date_to

    errors.add(:date_from, :after_date_to, message: "must be before date_to")
  end
end

# A link to another report that carries the current filters along, optionally
# overriding a few of them (docs/dev/reports/spec.md §2.1: "Chaque lien
# conserve les filtres dans l'URL"). E.g. clicking an account in the trial
# balance opens the general ledger with the same fiscal_year/dates, but
# account_from/account_to narrowed to that one account.
class Reports::DrillLinkComponent < ViewComponent::Base
  def initialize(path:, filters:, text:, overrides: {})
    @path      = path
    @filters   = filters
    @text      = text
    @overrides = overrides
  end

  def href
    query = @filters.attributes.merge(@overrides.stringify_keys).compact_blank.to_query
    "#{@path}?#{query}"
  end

  def call
    link_to @text, href
  end
end

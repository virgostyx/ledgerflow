# F12b step 2, collection: for each member in the scope at the reporting date, its annual accounts (R07 and R08, the same service as the screens, at that date)
# worked out INSIDE ITS OWN TENANT. No query here crosses companies: each member is read alone, then the figures are put side by side in Ruby.
# => a Hash (JSON-friendly) with the members, the warnings, the errors and the facts that tell which rules the group needs.
class Consolidation::Collect
  def self.call(group, date) = new(group, date).call

  def initialize(group, date)
    @group = group
    @date = date
  end

  def call
    warnings, errors = [], []
    collected = @group.members.includes(:member_entity, :stakes).order(:id).filter_map do |member|
      unless member.in_scope_on?(@date)
        warnings << "#{member.member_entity.name} is not in the scope at #{@date}: left out."
        next
      end
      read(member, warnings, errors)
    end
    full = collected.select { |m| m["method"] == "full" }
    { "reporting_date" => @date.iso8601, "members" => collected, "warnings" => warnings, "errors" => errors,
      "provisional" => collected.any? { |m| m["intermediate"] || m["fiscal_year_status"] != "closed" },
      "facts" => { "minority" => full.any? { |m| m["stake"] && !m["parent"] && BigDecimal(m["stake"]) < 100 }, "equity" => collected.any? { |m| m["method"] == "equity" },
                   "foreign" => collected.any? { |m| m["currency"] != @group.currency }, "intragroup" => intragroup?(collected),
                   "scope_change" => collected.any? { |m| m["scope_changed"] } } }
  end

  private

  def read(member, warnings, errors)
    entity = member.member_entity
    stake = member.stake_on(@date)
    errors << "#{entity.name}: no percentage held at #{@date}." if stake.nil? && !member.parent?
    ActsAsTenant.with_tenant(entity) do
      year = Accounting::FiscalYear.find_by("start_date <= :d AND end_date >= :d", d: @date)
      unless year
        errors << "#{entity.name}: no fiscal year contains #{@date}."
        return nil
      end

      report = Accounting::AnnualAccounts.new(fiscal_year: year, as_of: @date).call
      figures = report.rows_by_statement.values.flatten.to_h { |row| [ row.code, row.amount ] }
      intermediate = year.end_date != @date
      warnings << "#{entity.name}: its fiscal year ends #{year.end_date}, the statements are its situation at #{@date}." if intermediate
      warnings << "#{entity.name}: fiscal year #{year.year} is not closed: provisional." if year.status != "closed"
      errors << "#{entity.name}: its statements do not balance by #{format('%.2f', report.difference)}." unless report.balanced?
      errors << "#{entity.name}: #{report.unmapped.size} account(s) outside the headings of the annual accounts (#{report.unmapped.first(3).map(&:code).join(', ')}…)." if report.unmapped.any?
      { "member_id" => member.id, "entity_id" => entity.id, "name" => entity.name, "method" => member.method, "currency" => member.currency, "parent" => member.parent?,
        "stake" => stake&.to_s("F"), "fiscal_year" => year.year, "fy_start" => year.start_date.iso8601, "fiscal_year_status" => year.status, "intermediate" => intermediate,
        "scope_changed" => member.scope_changed_between?(year.start_date, @date), "figures" => figures.transform_values { |v| v.to_s("F") },
        "own" => Consolidation::Statements.own_of(figures.transform_values { |v| v.to_s("F") }).transform_values { |v| v.to_s("F") } }
    end
  end

  def intragroup?(collected)
    collected.any? { |m| ActsAsTenant.with_tenant(Entity.find(m["entity_id"])) { Accounting::Partner.where.not(intercompany_company_id: nil).exists? } }
  end
end

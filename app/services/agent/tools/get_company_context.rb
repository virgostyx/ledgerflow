# Where the books stand: the entity, its fiscal years, the periods locked, the journals (A02). The first thing the agent asks, and what it needs to turn "this year" or
# "last quarter" into dates.
class Agent::Tools::GetCompanyContext < Agent::Tools::Base
  tool_name "get_company_context"
  description "Describes the entity at hand: its name and legal form, its fiscal years (with their dates and status), the periods that are locked and its journals. " \
              "Use it first when the question depends on the year, a period or a journal, or to know which fiscal years exist. " \
              "Do not use it to get amounts: the report tools give those."
  permission "agent.use"
  tool_version 1
  input_schema type: "object", properties: {}, additionalProperties: false
  classify "data.*.entity.vat_number" => :tax_identifier, "data.*.entity.name" => :public_ref, "data.*.entity.legal_name" => :public_ref

  def call(_args, context)
    entity = context.entity
    current = Accounting::FiscalYear.current
    Agent::ToolResult.build(
      data: [ { "entity" => { "name" => entity.name, "legal_name" => entity.legal_name, "vat_number" => entity.vat_number, "country" => entity.country, "legal_form" => entity.legal_form },
                "fiscal_years" => fiscal_years(current),
                "locked_periods" => locked_periods,
                "journals" => journals } ],
      currency: "EUR", as_of: context.today, filters_applied: {}
    )
  end

  private

  def fiscal_years(current)
    Accounting::FiscalYear.order(:year).map do |year|
      { "year" => year.year, "start_date" => year.start_date.iso8601, "end_date" => year.end_date.iso8601, "status" => year.status, "current" => year.id == current&.id, "ref" => Agent::Refs.build("R07", year.id) }
    end
  end

  def locked_periods
    Accounting::PeriodLock.in_force.order(:starts_on).limit(50).map { |lock| { "kind" => lock.kind, "starts_on" => lock.starts_on.iso8601, "ends_on" => lock.ends_on.iso8601 } }
  end

  def journals
    Accounting::Journal.active.order(:code).map { |journal| { "code" => journal.code, "label" => journal.label_fr, "type" => journal.journal_type } }
  end
end

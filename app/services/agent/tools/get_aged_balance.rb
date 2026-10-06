# What customers owe, or what is owed to suppliers, aged by due date (A02, R04). One row per partner, biggest first by default.
class Agent::Tools::GetAgedBalance < Agent::Tools::Base
  tool_name "get_aged_balance"
  description "Returns the aged balance of customers (what they owe) or of suppliers (what is owed to them) at a date: per partner, the open amount not yet due and overdue by 1-30, 31-60, 61-90 and over 90 days, " \
              "the unallocated amounts (payments or credit notes not yet matched) and the total, with the overdue share. Biggest first by default. " \
              "Use it for who owes the most, who is late, or what a given customer owes. " \
              "Do not use it for the entries behind a partner's balance (use list_unreconciled or get_ledger) or for the balance of an account (use get_trial_balance)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[kind],
               properties: { kind: { type: "string", enum: %w[customer supplier], description: "customer: receivables; supplier: payables." },
                             as_of: { type: "string", format: "date", description: "Aged at this date (default: today)." },
                             partner_id: { type: "integer", minimum: 1, description: "Only this partner: the ID of a partner reference (partner:ID)." },
                             sort: { type: "string", enum: %w[total overdue name], description: "Order of the rows (default total, biggest first)." } }.merge(paging(max: 50))
  classify "data.*.partner" => :personal

  BUCKETS = Accounting::AgedBalanceQuery::BUCKETS

  def call(args, context)
    kind = args["kind"].to_sym
    as_of = date_arg(args, "as_of", context.today)
    rows = Accounting::AgedBalanceQuery.new(kind: kind, as_of: as_of).call
    rows = rows.select { |row| row.partner_id == args["partner_id"] } if args["partner_id"]
    ordered = sorted(rows, args["sort"] || "total")
    page_rows, next_cursor = page(ordered, args, default: 10, max: 50)
    Agent::ToolResult.build(
      data: page_rows.map { |row| row_for(row, as_of, kind) },
      totals: totals_for(rows, as_of, kind), currency: "EUR", as_of: as_of, next_cursor: next_cursor,
      filters_applied: { "kind" => kind, "as_of" => as_of.iso8601, "partner_id" => args["partner_id"], "sort" => args["sort"] || "total", "entries" => "validated only" }.compact,
      warnings: warnings(rows)
    )
  end

  private

  def sorted(rows, sort)
    case sort
    when "name"    then rows
    when "overdue" then rows.sort_by { |row| -row.overdue }
    else rows.sort_by { |row| -row.total }
    end
  end

  def row_for(row, as_of, kind)
    { "partner" => row.partner_name, "not_due" => money(row.not_due), "days_1_30" => money(row.days_1_30), "days_31_60" => money(row.days_31_60), "days_61_90" => money(row.days_61_90),
      "over_90" => money(row.over_90), "unallocated" => money(row.unallocated), "total" => money(row.total), "overdue" => money(row.overdue),
      "overdue_percent" => row.overdue_pct&.to_s("F"), "ref" => Agent::Refs.build("R04", as_of, kind, row.partner_id || "none") }
  end

  def totals_for(rows, as_of, kind)
    sum = Accounting::AgedBalanceQuery.totals(rows)
    BUCKETS.index_with { |bucket| money(sum[bucket]) }.transform_keys(&:to_s).merge("unallocated" => money(sum.unallocated), "total" => money(sum.total), "overdue" => money(sum.overdue),
                                                                                     "ref" => Agent::Refs.build("R04", as_of, kind, "total"))
  end

  def warnings(rows)
    orphan = rows.find { |row| row.partner_id.nil? }
    orphan ? [ "Open amounts without a partner: #{money(orphan.total)} EUR. They are in the totals." ] : []
  end
end

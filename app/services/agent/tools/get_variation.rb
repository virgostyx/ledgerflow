# What explains the change of an item between two periods (A08): the biggest contributors, by account, partner or month, summed in SQL by the variation query.
class Agent::Tools::GetVariation < Agent::Tools::Base
  tool_name "get_variation"
  description "Compares the validated movements (debit minus credit) of the accounts starting with a code between two periods and lists the biggest contributors to the change, by account, partner or calendar month: " \
              "both amounts, the change, its share of the total and the largest single line. Use it for 'why did this item change?': main contributor, one-off movement (a line over 30 percent of the change), new partner, calendar effect. " \
              "Do not use it for one balance (get_trial_balance) or for the entries behind a contributor (get_ledger)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[account_prefix first_from first_to second_from second_to],
               properties: { account_prefix: { type: "string", pattern: "^\\d{1,6}$", description: "The start of the account codes, such as 61 or 604000." },
                             first_from: { type: "string", format: "date", description: "Start of the first (earlier) period." }, first_to: { type: "string", format: "date", description: "End of the first period." },
                             second_from: { type: "string", format: "date", description: "Start of the second period." }, second_to: { type: "string", format: "date", description: "End of the second period." },
                             group_by: { type: "string", enum: Accounting::VariationQuery::GROUPS.keys, description: "account (default), partner, or month (calendar month, to compare the same month of both periods)." },
                             limit: { type: "integer", minimum: 1, maximum: 20, description: "How many contributors (default 10)." } }
  classify "data.*.account_label" => :public_ref, "data.*.account_code" => :public_ref, "data.*.partner" => :personal

  def call(args, context)
    first, second = range(args, "first"), range(args, "second")
    return { "error" => "invalid_arguments", "message" => "A period ends before it starts." } unless first && second

    result = Accounting::VariationQuery.new(account_prefix: args["account_prefix"], first: first, second: second, group_by: args["group_by"] || "account", limit: args["limit"] || 10).call
    @accounts = Accounting::Account.where(code: result.rows.map(&:key)).pluck(:code, :id).to_h
    Agent::ToolResult.build(
      data: result.rows.map { |row| row_for(row, args["group_by"] || "account", result.change_total) },
      totals: { "first_period" => money(result.first_total), "second_period" => money(result.second_total), "change" => money(result.change_total), "others_change" => money(result.others_change), "groups" => result.groups.to_s },
      currency: "EUR", as_of: second.end, truncated: result.groups > result.rows.size,
      filters_applied: { "account_prefix" => args["account_prefix"], "first" => "#{first.begin}..#{first.end}", "second" => "#{second.begin}..#{second.end}", "group_by" => args["group_by"] || "account", "entries" => "validated only" },
      warnings: warnings(first, second, result)
    )
  end

  private

  def range(args, name)
    from, to = Date.iso8601(args["#{name}_from"]), Date.iso8601(args["#{name}_to"])
    from <= to ? from..to : nil
  end

  def row_for(row, group_by, total_change)
    base = { "first" => money(row.first), "second" => money(row.second), "change" => money(row.change), "largest_line_second_period" => money(row.largest_line),
             "new_in_second_period" => (row.first.zero? && !row.second.zero?),
             "share_of_total_change_percent" => percent(row.change, total_change), "largest_line_percent_of_change" => percent(row.largest_line, row.change.abs) }.compact
    case group_by
    when "account" then base.merge("account_code" => row.key, "account_label" => row.label, "ref" => (Agent::Refs.build("account", accounts[row.key]) if accounts[row.key]))
    when "partner" then base.merge("partner" => row.label.presence || "(no partner)", "ref" => (Agent::Refs.build("partner", row.key) if row.key.present?))
    else base.merge("month" => row.key)
    end.compact
  end

  # code => id of the accounts of the rows (one query for the whole list).
  def accounts = @accounts ||= {}

  def money(amount) = Agent::ToolResult.money(amount)

  def percent(part, whole) = whole.zero? ? nil : money(part / whole * 100)

  def warnings(first, second, result)
    notes = [ "Amounts are debit minus credit: income accounts show negative figures; a negative change on an income account is more income." ]
    days = ->(range) { (range.end - range.begin).to_i + 1 }
    notes << "The periods do not have the same length (#{days.call(first)} and #{days.call(second)} days): compare with care." if days.call(first) != days.call(second)
    notes << "The periods overlap: the change counts some movements twice." if first.cover?(second.begin) || second.cover?(first.begin)
    notes << "Only the #{result.rows.size} biggest contributors of #{result.groups} are listed; the rest adds up to #{money(result.others_change)}." if result.groups > result.rows.size
    notes
  end
end

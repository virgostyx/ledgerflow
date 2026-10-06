# Finds accounts of the chart by a word of their code or label (A02). The agent uses it to name an account exactly, never to guess one.
class Agent::Tools::SearchAccounts < Agent::Tools::Base
  tool_name "search_accounts"
  description "Searches the chart of accounts of this entity by a code or a word of the label (French or Dutch): returns the code, the label, the class, the type and the normal balance. " \
              "Use it to find the exact account behind a name or a number before reading its ledger or balance. " \
              "Do not use it for amounts: use the balance or the ledger tools."
  permission "records.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[q],
               properties: { q: { type: "string", maxLength: 60, description: "A code (or its start) or a word of the label." },
                             include_inactive: { type: "boolean", description: "Also return archived accounts (default false)." } }.merge(paging(max: 50))
  classify "data.*.label" => :public_ref, "data.*.code" => :public_ref

  def call(args, _context)
    # digits are the start of a code (as in a chart), anything else is a word of a label
    accounts = args["q"].match?(/\A\d+\z/) ? Accounting::Account.where("code LIKE ?", "#{Accounting::Account.sanitize_sql_like(args['q'])}%") : Accounting::Account.search(args["q"], "label_fr", "label_nl")
    accounts = accounts.order(:code)
    accounts = accounts.active unless args["include_inactive"]
    rows, next_cursor = page(accounts, args, default: 25, max: 50)
    Agent::ToolResult.build(
      data: rows.map { |account| { "code" => account.code, "label" => account.label_fr, "class" => account.account_class, "type" => account.account_type, "normal_balance" => account.normal_balance,
                                   "active" => account.active, "ref" => Agent::Refs.build("account", account.id) } },
      filters_applied: { "q" => args["q"], "include_inactive" => args["include_inactive"] == true }, next_cursor: next_cursor
    )
  end
end

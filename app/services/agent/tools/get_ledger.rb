# The ledger of one account (A02, R02, R03): its lines in date order with the running balance, optionally of one partner or journal. Validated entries only.
class Agent::Tools::GetLedger < Agent::Tools::Base
  MAX_LINES = 5_000

  tool_name "get_ledger"
  description "Returns the ledger of one account for a period: the opening balance, each line (date, entry reference, label, debit, credit, running balance, partner, lettering) and the totals. " \
              "It can be narrowed to one partner, one journal, or to lettered or unlettered lines. Validated entries only. " \
              "Use it to see what is behind the balance of an account or to find the biggest movements. " \
              "Do not use it to compare many accounts (use get_trial_balance) or for what a customer owes in total (use get_aged_balance)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[account],
               properties: { account: { type: "string", pattern: "^\\d{1,10}$", maxLength: 10, description: "The exact account code, e.g. 604000. Find it with search_accounts." },
                             fiscal_year: { type: "integer", minimum: 1900, maximum: 2200, description: "The fiscal year, by its year number (default: the current one)." },
                             date_from: { type: "string", format: "date", description: "Start of the period (default: start of the year)." },
                             date_to: { type: "string", format: "date", description: "End of the period (default: end of the year)." },
                             partner_id: { type: "integer", minimum: 1, description: "Only this partner's lines: the ID of a partner reference (partner:ID)." },
                             journal: { type: "string", maxLength: 8, description: "Only this journal, by its code." },
                             lettering: { type: "string", enum: %w[lettered unlettered], description: "Only lettered or only unlettered lines." } }.merge(paging(max: 100))
  classify "data.*.label" => :free_text, "data.*.partner" => :personal, "data.*.reference" => :public_ref

  def call(args, context)
    account = Accounting::Account.find_by(code: args["account"]) or raise Agent::ToolError.new("not_found", "There is no account #{args['account']}: look for it with search_accounts.")
    year = fiscal_year_from(args)
    from, to = date_arg(args, "date_from", year.start_date), date_arg(args, "date_to", year.end_date)
    raise Agent::ToolError.new("invalid_arguments", "date_from must not be after date_to.") if from > to

    query = Accounting::GeneralLedgerQuery.new(account: account, fiscal_year: year, date_from: from, date_to: to, partner: partner_from(args), journal: journal_from(args), lettering: args["lettering"]&.to_sym)
    count = query.line_count
    raise Agent::ToolError.new("too_large", "This account has #{count} lines in the period: narrow the dates or give a partner or a journal.") if count > MAX_LINES

    lines = query.call
    debit, credit = query.totals
    rows, next_cursor = page(lines, args, default: 50, max: 100)
    Agent::ToolResult.build(
      data: rows.map { |line| row_for(line) },
      totals: { "opening_balance" => money(query.opening_balance), "debit" => money(debit), "credit" => money(credit),
                "closing_balance" => money(lines.last&.running_balance || query.opening_balance), "ref" => ref(year, account, from, to) },
      currency: "EUR", as_of: to, next_cursor: next_cursor,
      filters_applied: { "account" => account.code, "account_label" => account.label_fr, "balance_sense" => "#{account.normal_balance} (a positive balance is a #{account.normal_balance} balance)",
                         "fiscal_year" => year.year, "date_from" => from.iso8601, "date_to" => to.iso8601, "partner_id" => args["partner_id"], "journal" => args["journal"],
                         "lettering" => args["lettering"], "entries" => "validated only" }.compact,
      warnings: Array(("The fiscal year #{year.year} is not closed: these figures can still change." unless year.closed?))
    )
  end

  private

  def partner_from(args)
    return unless args["partner_id"]

    Accounting::Partner.find_by(id: args["partner_id"]) || raise(Agent::ToolError.new("not_found", "No such partner: look for it with search_partners."))
  end

  def journal_from(args)
    return unless args["journal"]

    Accounting::Journal.find_by(code: args["journal"]) || raise(Agent::ToolError.new("not_found", "There is no journal #{args['journal']}."))
  end

  def row_for(line)
    { "date" => line.entry_date.iso8601, "reference" => line.reference, "label" => line.label, "debit" => money(line.debit), "credit" => money(line.credit),
      "running_balance" => money(line.running_balance), "partner" => line.partner_name, "lettering" => line.lettering_code, "ref" => Agent::Refs.build("entry", line.journal_entry_id) }
  end

  def ref(year, account, from, to) = Agent::Refs.build("R02", year.id, account.id, "#{from.iso8601}..#{to.iso8601}")
end

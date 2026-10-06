# The bank reconciliation of one bank account at a date (A02, R06): the statement balance, the accounting balance, what is booked and not on the statement, what is on the
# statement and not booked, and the gap.
class Agent::Tools::GetBankReconciliation < Agent::Tools::Base
  LISTED = 20

  tool_name "get_bank_reconciliation"
  description "Returns the bank reconciliation of a bank account at a date: statement balance, accounting balance, the items booked but not on the statement, the items on the statement but not booked, the expected balance and the gap. " \
              "Use it to explain why the bank and the books differ. Give the code of the bank journal; if the entity has only one bank account it may be left out. " \
              "Do not use it for the movements of the bank account (use get_ledger on the account) or for open invoices (use get_aged_balance)."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { journal: { type: "string", maxLength: 8, description: "The code of the bank journal of the account." },
                             as_of: { type: "string", format: "date", description: "Reconciled at this date (default: today)." } }
  classify "data.*.bank_account" => :public_ref, "data.*.booked_not_on_statement.*.label" => :free_text, "data.*.on_statement_not_booked.*.label" => :free_text

  def call(args, context)
    account = bank_account_from(args)
    as_of = date_arg(args, "as_of", context.today)
    result = Accounting::BankReconciliationQuery.new(bank_account: account, as_of: as_of).call
    ref = Agent::Refs.build("R06", account.id, as_of)
    Agent::ToolResult.build(
      data: [ row_for(account, result, ref) ],
      totals: { "gap" => money(result.gap), "ref" => ref }, currency: account.currency, as_of: as_of,
      filters_applied: { "bank_account" => account.label_fr, "journal" => account.journal.code, "as_of" => as_of.iso8601, "entries" => "validated only" },
      warnings: warnings(result)
    )
  end

  private

  def bank_account_from(args)
    accounts = Accounting::BankAccount.active.includes(:journal).to_a
    found = args["journal"] ? accounts.find { |account| account.journal.code == args["journal"] } : (accounts.first if accounts.one?)
    return found if found

    available = accounts.map { |account| "#{account.journal.code} (#{account.label_fr})" }.to_sentence
    raise Agent::ToolError.new(accounts.empty? ? "not_found" : "invalid_arguments", accounts.empty? ? "This entity has no active bank account." : "Say which bank journal: #{available}.")
  end

  def row_for(account, result, ref)
    { "bank_account" => account.label_fr, "currency" => result.currency, "statement_balance" => money(result.statement_balance), "accounting_balance" => money(result.accounting_balance),
      "booked_not_on_statement_total" => money(result.bn_total), "on_statement_not_booked_total" => money(result.sn_total),
      "expected_balance" => money(result.expected_balance), "gap" => money(result.gap),
      "statements_with_broken_chain" => result.chain_breaks.size, "statements_to_review" => result.to_review.size,
      "booked_not_on_statement" => result.bn.first(LISTED).map { |item| item_row(item, entry: true) },
      "on_statement_not_booked" => result.sn.first(LISTED).map { |item| item_row(item, entry: false) },
      "fx_difference" => (money(result.fx_difference) if result.fx_difference), "ref" => ref }.compact
  end

  def item_row(item, entry:)
    { "date" => item.date.iso8601, "label" => item.label, "reference" => item.reference, "amount" => money(item.amount),
      "ref" => (Agent::Refs.build("entry", item.journal_entry_id) if entry && item.journal_entry_id) }.compact
  end

  def warnings(result)
    notes = []
    notes << "The lists show the first #{LISTED} items only (#{result.bn.size} booked not on the statement, #{result.sn.size} on the statement not booked)." if [ result.bn.size, result.sn.size ].max > LISTED
    notes << "The gap is not zero: the bank and the books do not reconcile at this date." if result.gap.nonzero?
    notes << "#{result.chain_breaks.size} statement(s) do not chain with the previous balance." if result.chain_breaks.any?
    notes
  end
end

# Proposes an entry to the person (A07). It writes nothing: the server checks the proposal, and what passes is kept to be shown to the person as a card, who decides with a click. A proposal that does not
# pass comes back with what to correct.
class Agent::Tools::ProposeEntry < Agent::Tools::Base
  LINE = { type: "object", additionalProperties: false, required: %w[account side],
           properties: { account: { type: "string", pattern: "^\\d{4,10}$", description: "Code of an account that exists in this entity's chart (checked with search_accounts)." },
                         side: { type: "string", enum: %w[debit credit] }, amount: { type: "string", description: "Decimal string with at most two decimals, such as 1210.50, in euros." },
                         currency: { type: "string", pattern: "^[A-Z]{3}$" }, amount_currency: { type: "string", description: "For a foreign currency line instead of amount." },
                         partner_id: { type: "integer", minimum: 1 }, label: { type: "string", maxLength: 120 }, vat_grid: { type: "integer", description: "Grid of the VAT return." },
                         vat_amount: { type: "string", description: "Base on a base grid line, tax on a tax grid line." }, due_date: { type: "string", format: "date" } } }.freeze

  tool_name "propose_entry"
  description "Proposes a balanced journal entry for the person to create as a draft with one click; nothing is written by you. Use it when asked to book or prepare an entry, after reading the chart (search_accounts), the partner and similar past entries. " \
              "The server checks it (balance to the cent, accounts, open period, VAT, currency rates) and returns what to correct: correct and call again at most twice, then explain the problem to the person. " \
              "Never invent an account: if the right one does not exist, explain which account would be needed and why, and refer to an accountant. Do not use it to change or validate an existing entry."
  permission "agent.propose"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[journal entry_date description lines rationale certainty],
               properties: { journal: { type: "string", maxLength: 8, description: "Journal code." }, entry_date: { type: "string", format: "date", description: "Accounting date." }, document_date: { type: "string", format: "date" },
                             reference: { type: "string", maxLength: 40, description: "The partner's document reference." }, description: { type: "string", maxLength: 200 },
                             document_total: { type: "string", description: "Total of the document; must equal the debit total." }, vat_rate: { type: "string", description: "VAT percentage, such as 21." },
                             lines: { type: "array", minItems: 2, maxItems: 30, items: LINE }, document_ref: { type: "string", description: "doc:ID of the document it comes from." },
                             rationale: { type: "string", maxLength: 1500, description: "Why this treatment, in plain words." }, source_refs: { type: "array", maxItems: 10, items: { type: "string" }, description: "The refs the treatment rests on." },
                             certainty: { type: "string", enum: Agent::Proposals::Entry::CERTAINTY, description: "confirmed (a reviewed passage says it), given (the books show it), general (a general rule, to check)." },
                             alternatives: { type: "array", maxItems: 3, items: { type: "object", additionalProperties: false, properties: { treatment: { type: "string" }, condition: { type: "string" } } } },
                             warnings: { type: "array", maxItems: 5, items: { type: "string" } } }
  classify "data.*.proposal.description" => :free_text, "data.*.proposal.rationale" => :free_text, "data.*.proposal.lines.*.label" => :free_text

  def call(args, context)
    result = Agent::Proposals::Entry.call(args, context: context, today: context.today)
    raise Agent::ToolError.new("invalid_proposal", "The proposal was not accepted. Correct: #{result.errors.join(' ')}") unless result.valid?

    Agent::ToolResult.build(data: [ { "valid" => true, "proposal" => result.normalized, "next" => "The person sees a card with this proposal and decides. The entry does not exist yet: say so, never that it was created." } ],
                            filters_applied: { "journal" => args["journal"], "entry_date" => args["entry_date"] }, warnings: result.warnings)
  end
end

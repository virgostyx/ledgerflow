# What the assistant writes a text from (A11): the style of the company, the language of the person it is for, and, for a reminder, the lines F09 would ask for, the ones it leaves out and why, the policy (what may be added
# and what may not), the history. Nothing here is written to the books.
class Agent::Tools::GetWritingContext < Agent::Tools::Base
  tool_name "get_writing_context"
  permission "agent.propose"
  tool_version 1
  description "Gives what a text is written from: the writing profile of the company (formality, formulas, signature, firmness per level, length), the language of the partner, and for a customer the lines a reminder would ask for with their " \
              "dates, amounts and invoice numbers, those left out and why (dispute, promise of payment), the reminder policy (what may be added) and the level. Use it BEFORE drafting any text with propose_text. " \
              "Do not use it for figures of the books (report tools) or to send anything: you cannot."
  input_schema type: "object", additionalProperties: false,
               properties: { partner_id: { type: "integer", minimum: 1, description: "The ID of the partner the text is for (partner:ID)." },
                             campaign: { type: "boolean", description: "For several reminders at once: the customers to remind (twenty at most) and those left out, with the reason." } }
  classify "data.*.partner.name" => :personal, "data.*.profile.signature" => :free_text, "data.*.profile.opening" => :free_text, "data.*.profile.closing" => :free_text, "data.*.profile.examples" => :free_text,
           "data.*.dunning.standard_text" => :free_text, "data.*.campaign.to_remind.*.name" => :personal, "data.*.campaign.left_out.*.name" => :personal, "data.*.dunning.eligible.*.invoice" => :public_ref

  def call(args, context)
    row = { "profile" => profile, "user_language" => context.locale.to_s }
    if args["partner_id"]
      partner = Accounting::Partner.find_by(id: args["partner_id"]) or raise Agent::ToolError.new("not_found", "There is no such partner: find it with search_partners.")
      row["partner"] = { "name" => partner.name, "language" => partner.language, "ref" => Agent::Refs.build("partner", partner.id) }
      row["dunning"] = dunning(partner, context) if context.allows?("dunning.prepare") && !partner.supplier?
    end
    row["campaign"] = campaign(context) if args["campaign"] && context.allows?("dunning.prepare")
    Agent::ToolResult.build(data: [ row.compact ], currency: "EUR", as_of: context.today, filters_applied: args.slice("partner_id"), warnings: warnings(args, row, context))
  end

  private

  def profile
    Agent::Setting.find_by(entity: ActsAsTenant.current_tenant)&.writing_profile.to_h.presence || { "note" => "No profile was set by the owners: write in a neutral, courteous style." }
  end

  def dunning(partner, context)
    facts = Agent::WritingFacts.for_partner(partner, as_of: context.today)
    language = partner.language.presence_in(Accounting::DunningTexts::LANGUAGES) || "en"
    {
      "eligible" => facts.eligible.map { |line| line_row(line) }, "excluded" => facts.excluded.map { |line, reason| line_row(line).merge("reason" => reason) }, "level" => facts.level,
      "total_overdue" => (money(facts.total) if facts.total), "reminder_fee" => (money(facts.fees) if facts.fees&.positive?), "may_add_interest" => facts.interest_enabled, "may_add_indemnity" => facts.indemnity_enabled,
      "interest_rate_percent" => (facts.policy.interest_rate.to_s("F") if facts.interest_enabled), "indemnity_amount" => (money(facts.policy.indemnity_amount) if facts.indemnity_enabled),
      "level_delays_days" => Accounting::DunningPolicy::LEVELS.map { |level| facts.policy.days_for(level) }, "blocked" => facts.blocked_reason,
      "standard_text" => (Accounting::DunningTexts.template(facts.policy, facts.level, language).last if facts.level), "standard_text_language" => language
    }.compact
  end

  def campaign(context)
    candidates, excluded, more = Agent::WritingFacts.campaign(as_of: context.today)
    { "to_remind" => candidates.map { |row| { "partner_id" => row.partner.id, "name" => row.partner.name, "level" => row.level, "total_overdue" => money(row.total), "oldest_days" => row.oldest_days, "language" => row.partner.language, "ref" => Agent::Refs.build("partner", row.partner.id) } },
      "left_out" => excluded.map { |partner, reason| { "partner_id" => partner.id, "name" => partner.name, "reason" => reason, "ref" => Agent::Refs.build("partner", partner.id) } }, "more_than_twenty" => more }.compact
  end

  def line_row(line)
    { "invoice" => line.reference, "due_date" => line.due_date.iso8601, "amount" => money(line.residual), "days_late" => line.days_late, "reminders_sent" => line.level_sent, "ref" => Agent::Refs.build("entry", line.entry_id) }.compact
  end

  def money(amount) = Agent::ToolResult.money(amount)

  def warnings(args, row, context)
    notes = []
    notes << "You may not read the reminders of this entity: write without them, and leave placeholders." if args["partner_id"] && !context.allows?("dunning.prepare")
    notes << "This customer gets no reminder: #{row.dig('dunning', 'blocked')} Say so and do not draft one." if row.dig("dunning", "blocked")
    notes << "The language of the partner is not known to the application: write in the language of the person and say so." if row["partner"] && !Accounting::DunningTexts::LANGUAGES.include?(row.dig("partner", "language").to_s)
    notes
  end
end

# The facts a reminder is written from (A11, F09), read where F09 reads them: the lines it would ask for, the lines it leaves out and why, the policy of the company (what it may add and what it may not), the history
# of the reminders. The assistant writes from these and from nothing else; a line in dispute or under a promise of payment gets no reminder.
module Agent::WritingFacts
  Line = Struct.new(:reference, :entry_id, :due_date, :residual, :days_late, :level_sent, keyword_init: true)
  Facts = Struct.new(:partner, :eligible, :excluded, :level, :total, :fees, :interest_enabled, :indemnity_enabled, :policy, :blocked_reason, keyword_init: true)

  # => Facts for one customer, as of a day.
  def self.for_partner(partner, as_of: Date.current)
    # Read only (a tool never writes): the policy the entity has, or the defaults it would be made with on first use.
    policy = Accounting::DunningPolicy.find_by(entity: ActsAsTenant.current_tenant) || Accounting::DunningPolicy.new(entity: ActsAsTenant.current_tenant)
    return Facts.new(partner: partner, eligible: [], excluded: [], policy: policy, blocked_reason: "This customer is marked 'do not remind'.") if partner.do_not_dun

    candidate = Accounting::DunningCandidates.new(as_of: as_of, policy: policy).call.find { |row| row.partner.id == partner.id }
    open_rows = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: as_of).call.select { |row| row.partner_id == partner.id && row.residual.positive? }
    flags = Accounting::JournalEntryLine.where(id: open_rows.map(&:line_id)).index_by(&:id)
    eligible_ids = candidate ? candidate.lines.map(&:line_id) : []
    excluded = open_rows.reject { |row| eligible_ids.include?(row.line_id) }.map { |row| [ line_of(row, flags[row.line_id]), reason_for(row, flags[row.line_id], policy, as_of, candidate) ] }
    eligible = candidate ? candidate.lines.map { |row| line_of(row, flags[row.line_id]) } : []
    Facts.new(partner: partner, eligible: eligible, excluded: excluded, level: candidate&.level, total: candidate&.total, fees: (candidate && policy.fee_for(candidate.level)), policy: policy,
              interest_enabled: policy.interest_enabled, indemnity_enabled: policy.indemnity_enabled,
              blocked_reason: (candidate ? nil : blocked_reason(excluded, open_rows, policy)))
  end

  # Several customers at once (A11): who gets a reminder and who is left out with the reason. Twenty at most, the latest to pay first.
  def self.campaign(as_of: Date.current, limit: 20)
    policy = Accounting::DunningPolicy.find_by(entity: ActsAsTenant.current_tenant) || Accounting::DunningPolicy.new(entity: ActsAsTenant.current_tenant)
    candidates = Accounting::DunningCandidates.new(as_of: as_of, policy: policy).call
    others = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: as_of).call.select { |row| row.partner_id && row.residual.positive? }.map(&:partner_id).uniq - candidates.map { |row| row.partner.id }
    excluded = Accounting::Partner.where(id: others).order(:name).limit(limit).map { |partner| [ partner, for_partner(partner, as_of: as_of).blocked_reason || "left out of the reminders" ] }
    [ candidates.first(limit), excluded, candidates.size > limit ]
  end

  def self.line_of(row, flag)
    Line.new(reference: row.reference, entry_id: row.journal_entry_id, due_date: row.due_date, residual: row.residual, days_late: row.age_days, level_sent: flag&.dunning_level.to_i)
  end
  private_class_method :line_of

  def self.reason_for(row, flag, policy, as_of, candidate)
    return "in dispute" if flag&.disputed
    return "payment promised until #{flag.payment_promised_on.iso8601}" if flag&.payment_promised_on && flag.payment_promised_on >= as_of
    return "reminded recently (#{flag.last_dunned_at.to_date.iso8601})" if flag&.last_dunned_at && flag.last_dunned_at > policy.min_days_between.days.ago
    return "not overdue enough for a first reminder" if row.age_days < policy.days_for(1)

    candidate ? "left out of the reminder" : "below the minimum amount of a reminder"
  end
  private_class_method :reason_for

  def self.blocked_reason(excluded, open_rows, policy)
    return "This customer has nothing overdue to remind." if open_rows.empty?
    return "Nothing can be reminded: #{excluded.map(&:last).uniq.to_sentence}." if excluded.any?

    "The total is below the minimum of a reminder (#{Agent::ToolResult.money(policy.min_amount)})."
  end
  private_class_method :blocked_reason
end

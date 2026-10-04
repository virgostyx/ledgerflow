# Prepares the reminders of the day (F09): one run, one pending item per customer proposed by Accounting::DunningCandidates, each with its lines and
# the text of its level in the customer's language. Nothing is sent from here. A customer already in a campaign of the same day is not made a second
# item: the first is returned in `refused`, so that the screen can link to it (criterion 7).
class Accounting::PrepareDunningRun
  # `only_level` and `only_channel` narrow what is prepared (the automatic sending of the first level, by e-mail only); `auto` marks such a run.
  def self.call(user:, on: Date.current, only_level: nil, only_channel: nil, auto: false)
    ctx    = LightService::Context.make(run: nil, refused: [])
    entity = ActsAsTenant.current_tenant
    policy = Accounting::DunningPolicy.for(entity)
    rows   = Accounting::DunningCandidates.new(as_of: on, policy: policy).call
    rows   = rows.select { |r| r.level == only_level } if only_level
    rows   = rows.select { |r| r.channel == only_channel } if only_channel
    taken  = Accounting::DunningItem.where(partner_id: rows.map { |r| r.partner.id }, run_on: on, excluded: false).includes(:run).index_by(&:partner_id)
    ctx[:refused] = rows.filter_map { |r| { partner: r.partner, item: taken[r.partner.id] } if taken[r.partner.id] }
    rows = rows.reject { |r| taken[r.partner.id] }
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.nobody")) } if rows.empty?

    ApplicationRecord.transaction do
      run = Accounting::DunningRun.create!(created_by: user, run_on: on, auto: auto)
      rows.each { |row| item_for(run, row, policy, entity, on) }
      ctx[:run] = run
    end
    ctx
  end

  def self.item_for(run, row, policy, entity, on)
    charges = Accounting::DunningCharges.call(policy: policy, level: row.level, rows: row.lines)
    item = run.items.create!(partner: row.partner, run_on: on, level: row.level, proposed_level: row.level, total: row.total, channel: row.channel,
                             recipient: row.recipient, language: row.partner.language, **charges)
    row.lines.each { |l| item.item_lines.create!(line_id: l.line_id, amount: l.residual, due_date: l.due_date) }
    item.update!(Accounting::DunningMessage.new(item: item, rows: row.lines, policy: policy, entity: entity, on: on).render)
  end
  private_class_method :item_for
end

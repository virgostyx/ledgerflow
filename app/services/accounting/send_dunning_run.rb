# The validation of a run (F09): what the user left in is queued for delivery, nothing else goes. Before queueing, each item is checked again against
# the situation now, because the preparation may be old: a level that skips one needs its confirmation, a customer marked "do not remind" since is
# left, and so is an item whose lines have been disputed, promised, settled... since. Those come back in `blocked`, with the reason, still pending.
class Accounting::SendDunningRun
  def self.call(run:, user:)
    ctx = LightService::Context.make(run: run, blocked: [])
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.already_sent")) } unless run.prepared?

    current = Accounting::DunningCandidates.new(as_of: run.run_on).call.to_h { |row| [ row.partner.id, row.lines.map(&:line_id) ] }
    run.items.pending.where(excluded: false).includes(:partner, :item_lines).each do |item|
      reason = blocking_reason(item, current, run, user)
      if reason
        ctx[:blocked] << { item: item, reason: reason }
      else
        item.update!(status: :queued)
        Accounting::DunningItemJob.perform_later(item.id, user&.id)
      end
    end
    ctx
  end

  def self.blocking_reason(item, current, run, user)
    return "The text was written by the assistant: a person must validate this reminder before it goes out." if item.agent_written? && (run.auto? || user.nil?)
    return I18n.t("accounting.dunning.errors.do_not_remind") if item.partner.do_not_dun
    return I18n.t("accounting.dunning.errors.skips_level", level: item.level) if item.skips_level? && !item.skip_confirmed
    I18n.t("accounting.dunning.errors.changed") unless (item.item_lines.map(&:line_id) - current.fetch(item.partner_id, [])).empty?
  end
  private_class_method :blocking_reason
end

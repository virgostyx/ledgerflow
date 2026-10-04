# A bounce reported for a reminder that went out (F09): kept on the item with the reason, flagged on the customer, and the lines go back to being
# asked for, as if it had not been sent. The mail server's report arrives outside the application, so a person records it.
class Accounting::RecordDunningBounce
  def self.call(item:, reason:)
    ctx = LightService::Context.make(item: item)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.not_sent")) } unless item.sent? && item.email?

    ApplicationRecord.transaction do
      item.update!(status: :bounced, error: reason.to_s.truncate(500).presence || "Bounced")
      item.partner.update!(email_bounced_at: Time.current)
      item.item_lines.includes(:line).each { |il| rewind(il.line, except: item) }
    end
    ctx
  end

  # The line is as it was before this item: the level and date of the last other reminder that went out for it, or none.
  def self.rewind(line, except:)
    last = Accounting::DunningItem.sent.joins(:item_lines).where(dunning_item_lines: { line_id: line.id }).where.not(id: except.id).order(:sent_at).last
    line.update_columns(dunning_level: last&.level.to_i, last_dunned_at: last&.sent_at)
  end
  private_class_method :rewind
end

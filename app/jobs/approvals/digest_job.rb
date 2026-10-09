# Every morning (B01a): each approver with something waiting gets one e-mail, once a day, unless they asked for no e-mail. Counts and a link only.
class Approvals::DigestJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each do |entity|
      next unless entity.feature?(:b01a)

      ActsAsTenant.with_tenant(entity) { UserEntity.current.includes(:user, :custom_role).where(notify_by_email: true).each { |membership| tell(entity, membership) } }
    end
  end

  private

  def tell(entity, membership)
    return unless membership.allows?("approvals.approve")

    rows = Approvals::Inbox.for(membership.user)
    return if rows.empty?

    # the record of the mail sent today is what keeps it to one a day
    Accounting::Notification.create!(user: membership.user, event: "approval_digest:#{Date.current.iso8601}", subject: entity, channel: :email)
    Approvals::DigestMailer.pending(user: membership.user, entity: entity, count: rows.size, overdue: rows.count { |row| row.invoice.due_date && row.invoice.due_date < Date.current }).deliver_now
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil # already told today
  end
end

# Every morning (B01a): each approver with something waiting gets one e-mail, once a day, unless they asked for no e-mail. Counts and a link only.
# The approvers are those of the entity the requests are in, nobody else's.
class Approvals::DigestJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each do |entity|
      next unless entity.feature?(:b01a)

      ActsAsTenant.with_tenant(entity) do
        directory = Approvals::Directory.new(entity)
        directory.mailable.each { |membership| tell(entity, membership, directory) if directory.approving?(membership.user_id) }
      end
    end
  end

  private

  def tell(entity, membership, directory)
    rows = Approvals::Inbox.for(membership.user, {}, directory: directory)
    return if rows.empty?

    # the record of the mail sent today is what keeps it to one a day
    Accounting::Notification.create!(user: membership.user, event: "approval_digest:#{Date.current.iso8601}", subject: entity, channel: :email)
    Approvals::DigestMailer.pending(user: membership.user, entity: entity, count: rows.size, overdue: rows.count { |row| row.invoice.due_date && row.invoice.due_date < Date.current }).deliver_now
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil # already told today
  end
end

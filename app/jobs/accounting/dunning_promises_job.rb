# Daily (F09): a line whose promise of payment is past comes back into the reminders, with a task on the customer for the person who took the promise.
# The date is cleared so that this happens once; a line paid meanwhile is only cleared. => number of tasks
class Accounting::DunningPromisesJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each.sum { |entity| ActsAsTenant.with_tenant(entity) { reintegrate } }
  end

  private

  def reintegrate
    today = Date.current
    lines = Accounting::JournalEntryLine.where("payment_promised_on < ?", today).includes(:partner, :journal_entry).to_a
    open  = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: today).call.select { |r| r.residual.positive? }.map(&:line_id).to_set
    lines.count do |line|
      line.update!(payment_promised_on: nil)
      next false unless open.include?(line.id) && line.partner

      Accounting::Task.create!(title: "Promise not kept: #{line.partner.name}, #{line.journal_entry.reference.presence || "entry #{line.journal_entry_id}"}",
                               kind: :client_question, target: line.partner, due_on: today, assignee: promised_by(line), author: promised_by(line))
    end
  end

  def promised_by(line)
    id = Accounting::AuditLog.for_record(line).for_action("dunning_promise").order(:id).last&.user_id
    User.find_by(id: id) if id && ActsAsTenant.current_tenant.user_entities.exists?(user_id: id)
  end
end

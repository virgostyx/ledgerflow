# F13a: takes a guided import back. A batch that holds only drafts is deleted with what it created (partners and accounts that something else
# uses are kept, and said). Once some of its entries were validated, nothing validated is deleted: they are reversed (F07), with a reason,
# and the drafts that remain are deleted. Nothing outside the batch is touched.
class Imports::Undo
  class Refused < StandardError; end

  def self.call(batch:, user:, reason: nil)
    raise Refused, "Only an imported batch can be taken back" unless batch.kind && batch.result == "imported"

    entries = Accounting::JournalEntry.where(import_batch_id: batch.id).includes(lines: :analytical_annotations).to_a
    posted  = entries.select(&:posted?)
    raise Refused, "A reason is required: the batch holds validated entries, which are reversed, not deleted" if posted.any? && reason.blank?

    kept = []
    ApplicationRecord.transaction do
      posted.each do |entry|
        result = Accounting::ReverseJournalEntry.call(entry: entry, reason: reason, user: user)
        raise Refused, "#{entry.reference}: #{result.message}" if result.failure?
      end
      entries.select(&:draft?).each(&:destroy!)
      Accounting::Partner.where(import_batch_id: batch.id).find_each { |partner| kept << "partner #{partner.name}" unless removed?(partner) }
      Accounting::Account.where(import_batch_id: batch.id).order(:code).reverse_each { |account| kept << "account #{account.code}" unless removed?(account) }
      batch.update!(result: "undone", undo_reason: reason, undone_by: user, undone_at: Time.current)
      Accounting::AuditLog.record!(auditable: batch, action: "guided_import_undone", user: user, reason: reason,
                                   payload: { batch_id: batch.id, kind: batch.kind, reversed: posted.size, deleted: entries.size - posted.size, kept: kept })
    end
    batch
  end

  # Deleted unless something else refers to it (a line, an invoice, a child): then it stays, and the batch says so.
  def self.removed?(record)
    ApplicationRecord.transaction(requires_new: true) { record.destroy }
  rescue ActiveRecord::InvalidForeignKey
    false
  end
  private_class_method :removed?
end

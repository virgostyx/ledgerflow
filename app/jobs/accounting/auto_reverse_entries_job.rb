# Daily (F07): the posted entries that asked for their own reversal (auto_reverse_on) get it, as a DRAFT dated like any reversal; a draft is
# never posted without a person. Idempotent: an entry that already has an active reversal is left alone. => number of drafts created
class Accounting::AutoReverseEntriesJob < ApplicationJob
  queue_as :default

  def perform
    ActsAsTenant.without_tenant { Accounting::JournalEntry.posted.where("auto_reverse_on <= ?", Date.current).pluck(:id, :entity_id) }.count do |id, entity_id|
      ActsAsTenant.with_tenant(Entity.find(entity_id)) do
        entry = Accounting::JournalEntry.find(id)
        Accounting::ReverseJournalEntry.call(entry: entry, draft: true, from: entry.auto_reverse_on,
                                             reason: I18n.t("accounting.journal_entries.scheduled_reversal_reason", date: entry.auto_reverse_on)).success?
      end
    end
  end
end

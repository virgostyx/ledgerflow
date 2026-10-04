# The number of open tasks about each of a list of things (F08), in one query, for the badges of the lists: an entry counts the tasks about its
# own lines too (a task made from a ledger line shows on its entry). => { id => count }
module Accounting::TaskBadges
  def self.counts(klass, ids)
    ids = Array(ids)
    return {} if ids.empty?

    counts = open_tasks.where(target_type: klass.name, target_id: ids).group(:target_id).count
    return counts unless klass == Accounting::JournalEntry

    lines = Accounting::JournalEntryLine.where(journal_entry_id: ids).pluck(:id, :journal_entry_id).to_h
    open_tasks.where(target_type: "Accounting::JournalEntryLine", target_id: lines.keys).group(:target_id).count.each do |line_id, count|
      entry_id = lines.fetch(line_id)
      counts[entry_id] = counts.fetch(entry_id, 0) + count
    end
    counts
  end

  def self.open_tasks = Accounting::Task.open_ones
end

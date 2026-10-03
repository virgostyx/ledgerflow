# F01: an access may be limited to some journals. NULL = every journal (all existing accesses are unchanged).
class AddJournalIdsToUserEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :user_entities, :journal_ids, :bigint, array: true
  end
end

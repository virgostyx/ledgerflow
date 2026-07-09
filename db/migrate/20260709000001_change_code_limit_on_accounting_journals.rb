class ChangeCodeLimitOnAccountingJournals < ActiveRecord::Migration[8.1]
  def change
    change_column :accounting_journals, :code, :string, limit: 8, null: false
  end
end

# F12a: the portfolio. Organizations group the entities of a firm or a group; each entity may have a person in charge; the last entity a user worked in is
# kept; and each night every entity writes its own health snapshot, from its own books only, so that the dashboard reads one small table and never the ledgers.
class CreatePortfolio < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :organization_memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member" # owner (manages the organization) / member
      t.timestamps
    end
    add_index :organization_memberships, %i[organization_id user_id], unique: true

    add_reference :entities, :organization, foreign_key: true
    add_reference :entities, :responsible, foreign_key: { to_table: :users }
    add_column :users, :last_entity_id, :bigint

    create_table :dossier_health_snapshots do |t|
      t.references :entity, null: false, foreign_key: true
      t.date     :taken_on, null: false
      t.datetime :computed_at, null: false
      t.string   :closing_status                       # open / in_progress / ready / closed
      t.integer  :closing_progress
      t.integer  :closing_year
      t.date     :next_vat_due_on
      t.boolean  :vat_overdue, null: false, default: false
      t.integer  :blocking_count                       # R19 (nil: never run)
      t.integer  :warning_count
      t.datetime :consistency_run_at
      t.integer  :unreconciled_bank_lines, null: false, default: 0
      t.integer  :oldest_unreconciled_days
      t.integer  :peppol_pending, null: false, default: 0
      t.integer  :peppol_anomalies, null: false, default: 0
      t.integer  :inbox_documents, null: false, default: 0
      t.integer  :overdue_tasks, null: false, default: 0
      t.decimal  :overdue_receivables, precision: 15, scale: 2, null: false, default: 0
      t.date     :last_posted_on
      t.jsonb    :details, null: false, default: {}
      t.timestamps
    end
    add_index :dossier_health_snapshots, %i[entity_id taken_on], unique: true
  end
end

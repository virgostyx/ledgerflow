# F08: tasks and comments about the thing they concern (an entry, a ledger line, an account, a partner, a document, a bank line, a period), and the
# notifications they raise. A comment is never deleted, only hidden; the mention a person gets is recorded once (unique key).
class CreateTasksCommentsNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_tasks do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :title, null: false
      t.text    :description
      t.integer :status, null: false, default: 0    # open / in_progress / blocked / done / cancelled
      t.integer :priority, null: false, default: 1  # low / normal / high
      t.integer :kind, null: false, default: 4      # missing_document / to_check / client_question / closing / other
      t.references :assignee, foreign_key: { to_table: :users }
      t.date    :due_on
      t.string  :target_type
      t.bigint  :target_id
      t.string  :anomaly_fingerprint                # a consistency anomaly (R19): the fingerprint is what stays the same from run to run
      t.references :author, foreign_key: { to_table: :users }
      t.datetime :completed_at
      t.references :completed_by, foreign_key: { to_table: :users }
      t.text     :question                          # what a third party is asked (external reply)
      t.datetime :external_expires_at               # until when the link sent to that third party answers
      t.timestamps
    end
    add_index :accounting_tasks, %i[entity_id status]
    add_index :accounting_tasks, %i[target_type target_id]
    add_index :accounting_tasks, :anomaly_fingerprint, where: "anomaly_fingerprint IS NOT NULL"

    create_table :accounting_comments do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :commentable_type, null: false
      t.bigint  :commentable_id, null: false
      t.references :parent, foreign_key: { to_table: :accounting_comments }
      t.references :author, foreign_key: { to_table: :users }   # nil: a third party who answered through a link
      t.string  :external_name
      t.text    :body, null: false
      t.bigint  :mentioned_user_ids, array: true, null: false, default: []
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :hidden_at
      t.references :hidden_by, foreign_key: { to_table: :users }
      t.datetime :edited_at
      t.timestamps
    end
    add_index :accounting_comments, %i[commentable_type commentable_id]

    create_table :accounting_notifications do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string  :event, null: false                  # task_assigned / mention / task_due / digest
      t.string  :subject_type
      t.bigint  :subject_id
      t.integer :channel, null: false, default: 0    # in_app / email
      t.jsonb   :data, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end
    add_index :accounting_notifications, %i[user_id event subject_type subject_id channel], unique: true, name: "idx_notifications_once"
    add_index :accounting_notifications, %i[user_id read_at]

    add_column :user_entities, :notify_by_email, :boolean, null: false, default: true
    add_column :user_entities, :notify_daily_digest, :boolean, null: false, default: false
  end
end

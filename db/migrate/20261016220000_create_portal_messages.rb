# B02c: a simple thread of messages per company between its portal people and the firm. A message is never edited nor deleted; a client's message can become a task of the firm.
class CreatePortalMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_threads do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.string :token, null: false
      t.timestamps
    end
    add_index :portal_threads, :token, unique: true

    create_table :portal_messages do |t|
      t.references :thread, null: false, foreign_key: { to_table: :portal_threads }
      t.references :entity, null: false, foreign_key: true
      t.string :author_kind, null: false # "client" or "firm"
      t.references :portal_user, foreign_key: true
      t.bigint :user_id # the person of the firm
      t.text :body, null: false
      t.bigint :task_id # the task a client's message was turned into, by the firm
      t.datetime :read_by_firm_at
      t.timestamps
    end
    add_index :portal_messages, %i[thread_id id]

    add_column :portal_uploads, :thread_id, :bigint # a document sent into the thread
  end
end

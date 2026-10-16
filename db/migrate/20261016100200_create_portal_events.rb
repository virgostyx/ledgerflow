# B02a: what the people from outside did (sign-in, reading, download, deposit, answer). Append-only in practice; each row is copied into the audit trail of the company
# (R18, actor_type portal_user) by an internal job, which sets mirrored_at: the portal itself never writes to the books.
class CreatePortalEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_events do |t|
      t.references :portal_user, foreign_key: true # nil when the person is not known (a failed sign-in)
      t.references :entity, foreign_key: true
      t.string :action, null: false
      t.string :target_token
      t.string :email_tried
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :mirrored_at
      t.timestamps
    end
    add_index :portal_events, :occurred_at
    add_index :portal_events, :mirrored_at, where: "mirrored_at IS NULL", name: "index_portal_events_not_mirrored"
  end
end

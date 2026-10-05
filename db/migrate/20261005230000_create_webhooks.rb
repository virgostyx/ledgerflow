# F13c: outgoing webhooks. A subscription (URL, events, a secret that signs what is sent) and the log of what was sent: one delivery per event and
# subscription, with its attempts, so that a failure is visible and can be sent again.
class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_subscriptions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string  :name, null: false
      t.string  :url, null: false
      t.text    :events, array: true, null: false, default: []
      t.string  :secret, null: false                       # encrypted
      t.string  :previous_secret                           # encrypted; signs too for a day after a rotation
      t.datetime :secret_rotated_at
      t.boolean :active, null: false, default: true
      t.datetime :suspended_at
      t.string  :suspended_reason
      t.integer :consecutive_failures, null: false, default: 0
      t.integer :max_failures, null: false, default: 10     # failed attempts in a row before the subscription is suspended
      t.datetime :last_delivery_at
      t.timestamps
    end

    create_table :webhook_deliveries do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :webhook_subscription, null: false, foreign_key: true
      t.references :replay_of, foreign_key: { to_table: :webhook_deliveries }
      t.string  :event, null: false
      t.string  :event_id, null: false                      # the same for every delivery of one event, and for its replays
      t.integer :payload_version, null: false, default: 1
      t.jsonb   :payload, null: false, default: {}
      t.string  :status, null: false, default: "pending"    # pending / delivered / failed (gave up) / held (the subscription is suspended)
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.integer :last_response_code
      t.string  :last_error
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :webhook_deliveries, %i[webhook_subscription_id created_at]
    add_index :webhook_deliveries, %i[status next_attempt_at]
  end
end

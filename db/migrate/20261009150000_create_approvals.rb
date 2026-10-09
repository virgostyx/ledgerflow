# B01a: the circuit that approves a purchase invoice (the "bon à payer") before it can be paid (docs/dev/signature/spec.md §4).
# New tables only, plus one column on invoices whose default (not_required) leaves every existing invoice as it is. Reversible.
class CreateApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :approval_policies do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :subject, null: false # purchase_invoice, payment_batch
      t.jsonb   :conditions, null: false, default: {}
      t.integer :priority, null: false, default: 100
      t.boolean :active, null: false, default: true
      t.integer :version, null: false, default: 1
      t.timestamps
    end

    create_table :approval_steps do |t|
      t.references :policy, null: false, foreign_key: { to_table: :approval_policies, on_delete: :cascade }
      t.integer :position, null: false
      t.integer :mode, null: false, default: 0 # any_of, all_of
      t.bigint  :approver_user_ids, array: true, null: false, default: []
      t.string  :approver_roles, array: true, null: false, default: []
      t.integer :service_hours
      t.references :escalate_to, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :approval_steps, %i[policy_id position], unique: true

    create_table :approval_requests do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :policy, foreign_key: { to_table: :approval_policies, on_delete: :nullify }
      t.integer :policy_version
      t.string  :subject_type, null: false
      t.bigint  :subject_id, null: false
      t.integer :current_step, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.string  :content_fingerprint, null: false, limit: 64
      t.references :submitted_by, foreign_key: { to_table: :users }
      t.datetime :submitted_at
      t.datetime :step_started_at
      t.datetime :decided_at
      t.string :invalidation_reason
      t.timestamps
    end
    add_index :approval_requests, %i[subject_type subject_id]
    add_index :approval_requests, %i[subject_type subject_id], unique: true, where: "status = 0", name: "index_approval_requests_one_pending_per_subject"

    create_table :approval_decisions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :request, null: false, foreign_key: { to_table: :approval_requests, on_delete: :cascade }
      t.integer :step_position, null: false
      t.references :approver, null: false, foreign_key: { to_table: :users }
      t.references :on_behalf_of, foreign_key: { to_table: :users } # the delegator, when a delegate decides
      t.integer :decision, null: false # approved, rejected, changes_requested, transferred
      t.text    :comment
      t.integer :channel, null: false, default: 0 # web, mobile, api
      t.string  :device_fingerprint
      t.string  :content_fingerprint, null: false, limit: 64 # what the person had in front of them
      t.datetime :decided_at, null: false
      t.timestamps
    end

    create_table :approval_delegations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :delegator, null: false, foreign_key: { to_table: :users }
      t.references :delegate, null: false, foreign_key: { to_table: :users }
      t.date   :starts_on, null: false
      t.date   :ends_on, null: false
      t.bigint :policy_ids, array: true, null: false, default: [] # empty: every policy
      t.string :reason, null: false
      t.timestamps
    end

    add_column :accounting_invoices, :payment_status, :integer, null: false, default: 0 # not_required
    add_index  :accounting_invoices, :payment_status
  end
end

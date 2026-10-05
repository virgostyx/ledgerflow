# F12b: consolidation of a group. The architecture and the controls; the accounting rules are DATA that a recorded validation switches on
# (consolidation_rule_validations), never code that applies itself. Consolidation entries live apart from the books of every company and change none of them.
class CreateConsolidation < ActiveRecord::Migration[8.1]
  def change
    create_table :consolidation_groups do |t|
      t.references :entity, null: false, foreign_key: true           # the parent company: the group lives in its books' scope
      t.string  :name, null: false
      t.string  :currency, limit: 3, null: false, default: "EUR"     # the currency of the consolidated statements
      t.timestamps
    end

    create_table :consolidation_members do |t|
      t.references :consolidation_group, null: false, foreign_key: true
      t.references :member_entity, null: false, foreign_key: { to_table: :entities }
      t.string  :method, null: false, default: "full"                 # full (global integration) / equity (simple equity method)
      t.string  :currency, limit: 3, null: false, default: "EUR"      # the currency this member keeps its accounts in
      t.date    :joined_on
      t.date    :left_on
      t.timestamps
    end
    add_index :consolidation_members, %i[consolidation_group_id member_entity_id], unique: true, name: "idx_consolidation_members_unique"

    create_table :consolidation_stakes do |t|                         # the percentage held, with its date of effect (the history is kept)
      t.references :consolidation_member, null: false, foreign_key: true
      t.decimal :percentage, precision: 5, scale: 2, null: false
      t.date    :effective_on, null: false
      t.timestamps
    end
    add_index :consolidation_stakes, %i[consolidation_member_id effective_on], unique: true, name: "idx_consolidation_stakes_unique"

    create_table :consolidation_mappings do |t|                       # a heading of a member (R07/R08) to a consolidated heading; none = same code
      t.references :consolidation_group, null: false, foreign_key: true
      t.references :consolidation_member, foreign_key: true           # nil = every member
      t.string :statement, null: false
      t.string :source_code, null: false
      t.string :consolidated_code, null: false
      t.timestamps
    end

    create_table :consolidation_rule_validations do |t|               # an accountant's validation of one rule, with the parameters that were validated
      t.references :consolidation_group, null: false, foreign_key: true
      t.string  :rule_key, null: false
      t.string  :validated_by_name, null: false
      t.string  :validated_by_title, null: false                      # e.g. "Chartered accountant, Firm X"
      t.date    :validated_on, null: false
      t.string  :reference, null: false                               # where it is written: the QUESTIONS.md section, a letter, a ticket
      t.text    :note
      t.jsonb   :parameters, null: false, default: {}
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :consolidation_rule_validations, %i[consolidation_group_id rule_key], where: "revoked_at IS NULL", unique: true, name: "idx_consolidation_validation_active"

    create_table :consolidation_runs do |t|
      t.references :consolidation_group, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.date    :reporting_date, null: false
      t.string  :status, null: false, default: "draft"                # draft / validated / frozen
      t.boolean :provisional, null: false, default: false             # a member whose year is open, or ends another day
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :validated_by, foreign_key: { to_table: :users }
      t.references :frozen_by, foreign_key: { to_table: :users }
      t.references :previous_run, foreign_key: { to_table: :consolidation_runs }
      t.jsonb   :figures, null: false, default: {}                    # what was collected and computed, while the run is a draft
      t.jsonb   :snapshot                                             # the frozen content
      t.string  :snapshot_sha256
      t.datetime :validated_at
      t.datetime :frozen_at
      t.timestamps
    end

    create_table :consolidation_entries do |t|
      t.references :consolidation_run, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string  :kind, null: false                                    # intragroup_balances / intragroup_flows / dividends / participation / intercompany_adjustment / adjustment
      t.string  :rule_key                                             # the rule that proposed it; nil when a person made it
      t.string  :comment, null: false
      t.references :document, foreign_key: { to_table: :accounting_documents }  # the supporting document (F03)
      t.references :created_by, foreign_key: { to_table: :users }
      t.jsonb :context, null: false, default: {}                    # e.g. the two members and the pair of headings an elimination is about
      t.timestamps
    end

    create_table :consolidation_entry_lines do |t|
      t.references :consolidation_entry, null: false, foreign_key: true
      t.string  :statement, null: false
      t.string  :code, null: false                                    # a heading of the annual accounts
      t.string  :side, null: false                                    # debit / credit
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.timestamps
    end

    add_reference :accounting_partners, :intercompany_company, foreign_key: { to_table: :entities }
  end
end

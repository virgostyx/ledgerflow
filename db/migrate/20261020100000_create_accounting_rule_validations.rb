# An accountant's validation of one accounting rule set of a company (VAT declaration, annual accounts...): who, in what capacity, when, where it is written.
# Until one is in force, the screens that depend on the rule show a "not validated" notice. See docs/dev/POINTS_A_VALIDER.md.
class CreateAccountingRuleValidations < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_rule_validations do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :rule_key, null: false
      t.string  :validated_by_name, null: false
      t.string  :validated_by_title, null: false     # e.g. "Chartered accountant, Firm X"
      t.date    :validated_on, null: false
      t.string  :reference, null: false              # where it is written: a letter, a ticket, a section of POINTS_A_VALIDER.md
      t.text    :note
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :accounting_rule_validations, %i[entity_id rule_key], where: "revoked_at IS NULL", unique: true, name: "idx_rule_validation_active"
  end
end

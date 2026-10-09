# B01a: above this amount (incl. VAT, in EUR), approving an invoice asks for a second factor given a moment ago. Empty: never asked. Reversible.
class AddStepUpThresholdToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :step_up_threshold, :decimal, precision: 15, scale: 2
  end
end

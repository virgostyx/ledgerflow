# R12: an analytical annotation becomes a share (percentage) of the line so one line can be
# split across several analytical accounts of an axis. Existing rows keep 100 %.
class AddPercentageToAnalyticalAnnotations < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_analytical_annotations, :percentage, :decimal, precision: 5, scale: 2, default: 100, null: false
    add_check_constraint :accounting_analytical_annotations, "percentage > 0 AND percentage <= 100",
                         name: "analytical_annotations_percentage_range"

    remove_index :accounting_analytical_annotations, name: "index_analytical_annotations_on_line_and_axis", unique: true,
                 column: %i[journal_entry_line_id analytical_axis_id]
    add_index :accounting_analytical_annotations, %i[journal_entry_line_id analytical_axis_id analytical_account_id],
              unique: true, name: "index_analytical_annotations_on_line_axis_account"
  end
end

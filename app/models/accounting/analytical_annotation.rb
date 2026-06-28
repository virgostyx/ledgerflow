class Accounting::AnalyticalAnnotation < ApplicationRecord
  self.table_name = "accounting_analytical_annotations"

  acts_as_tenant :entity

  belongs_to :journal_entry_line, class_name: "Accounting::JournalEntryLine",
             foreign_key: :journal_entry_line_id, inverse_of: :analytical_annotations
  belongs_to :analytical_axis,    class_name: "Accounting::AnalyticalAxis",
             foreign_key: :analytical_axis_id
  belongs_to :analytical_account, class_name: "Accounting::AnalyticalAccount",
             foreign_key: :analytical_account_id

  validates :analytical_axis_id, uniqueness: { scope: :journal_entry_line_id }
  validate  :account_belongs_to_axis

  private

  def account_belongs_to_axis
    return unless analytical_account.present? && analytical_axis.present?
    return if analytical_account.analytical_axis_id == analytical_axis_id

    errors.add(:analytical_account, :must_belong_to_axis)
  end
end

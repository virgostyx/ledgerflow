class Accounting::AnalyticalAnnotation < ApplicationRecord
  self.table_name = "accounting_analytical_annotations"

  acts_as_tenant :entity

  belongs_to :journal_entry_line, class_name: "Accounting::JournalEntryLine",
             foreign_key: :journal_entry_line_id, inverse_of: :analytical_annotations
  belongs_to :analytical_axis,    class_name: "Accounting::AnalyticalAxis",
             foreign_key: :analytical_axis_id
  belongs_to :analytical_account, class_name: "Accounting::AnalyticalAccount",
             foreign_key: :analytical_account_id

  validates :analytical_axis_id, uniqueness: { scope: %i[journal_entry_line_id analytical_account_id] }
  validates :percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validate  :account_belongs_to_axis
  validate  :axis_split_within_100

  private

  # Any remainder below 100 % is reported as "Non ventilé" by the analytic reports (R12).
  def axis_split_within_100
    return if journal_entry_line_id.blank? || analytical_axis_id.blank? || percentage.blank?

    others = self.class.where(journal_entry_line_id: journal_entry_line_id, analytical_axis_id: analytical_axis_id)
                       .where.not(id: id).sum(:percentage)
    errors.add(:percentage, :split_exceeds_100) if others + percentage > 100
  end

  def account_belongs_to_axis
    return unless analytical_account.present? && analytical_axis.present?
    return if analytical_account.analytical_axis_id == analytical_axis_id

    errors.add(:analytical_account, :must_belong_to_axis)
  end
end

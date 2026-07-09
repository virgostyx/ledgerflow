class Accounting::InvoiceLineAnnotation < ApplicationRecord
  self.table_name = "accounting_invoice_line_annotations"

  acts_as_tenant :entity

  belongs_to :invoice_line,      class_name: "Accounting::InvoiceLine",
             inverse_of: :analytical_annotations
  belongs_to :analytical_axis,   class_name: "Accounting::AnalyticalAxis"
  belongs_to :analytical_account, class_name: "Accounting::AnalyticalAccount"

  validates :analytical_axis_id, uniqueness: { scope: :invoice_line_id }
  validate  :account_belongs_to_axis

  private

  def account_belongs_to_axis
    return unless analytical_account.present? && analytical_axis.present?
    return if analytical_account.analytical_axis_id == analytical_axis_id

    errors.add(:analytical_account, :must_belong_to_axis)
  end
end

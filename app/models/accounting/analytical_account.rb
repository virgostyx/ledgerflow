class Accounting::AnalyticalAccount < ApplicationRecord
  self.table_name = "accounting_analytical_accounts"

  acts_as_tenant :entity

  belongs_to :analytical_axis, class_name: "Accounting::AnalyticalAxis",
             foreign_key: :analytical_axis_id
  has_many   :analytical_annotations, class_name: "Accounting::AnalyticalAnnotation",
             foreign_key: :analytical_account_id, dependent: :destroy

  validates :code,     presence: true,
                       uniqueness: { scope: :analytical_axis_id, case_sensitive: false }
  validates :code,     length: { maximum: 40 }
  validates :label_fr, presence: true

  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:code) }

  # Kept by an application (BudgetFlow, through the API): it commands the code, the label and whether the account is active.
  def managed? = external_ref.present?

  def destroyable?
    !managed? && analytical_annotations.none?
  end
end

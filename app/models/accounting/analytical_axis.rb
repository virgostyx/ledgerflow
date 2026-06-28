class Accounting::AnalyticalAxis < ApplicationRecord
  self.table_name = "accounting_analytical_axes"

  acts_as_tenant :entity

  has_many :analytical_accounts, class_name: "Accounting::AnalyticalAccount",
           foreign_key: :analytical_axis_id, dependent: :destroy
  has_many :analytical_annotations, class_name: "Accounting::AnalyticalAnnotation",
           foreign_key: :analytical_axis_id, dependent: :destroy

  validates :code,     presence: true, uniqueness: { scope: :entity_id, case_sensitive: false }, length: { maximum: 10 }
  validates :label_fr, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:code) }

  def required_for_class?(account_class)
    required_for_account_classes.include?(account_class.to_i)
  end
end

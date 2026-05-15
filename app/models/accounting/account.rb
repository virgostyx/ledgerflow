class Accounting::Account < ApplicationRecord
  self.table_name = "accounting_accounts"

  include Accounting::MonetaryPrecision
  include Accounting::Auditable

  enum :account_type,   { asset: 0, liability: 1, equity: 2, revenue: 3, expense: 4 }
  enum :normal_balance, { debit: 0, credit: 1 }

  belongs_to :parent, class_name: "Accounting::Account", optional: true,
             foreign_key: :parent_id
  has_many   :children, class_name: "Accounting::Account", foreign_key: :parent_id,
             dependent: :restrict_with_error

  validates :code,           presence: true, uniqueness: true, length: { maximum: 10 }
  validates :label_fr,       presence: true
  validates :account_class,  presence: true,
                             inclusion: { in: 1..7 }
  validates :account_type,   presence: true
  validates :normal_balance, presence: true

  scope :active,    -> { where(active: true) }
  scope :leaf,      -> { where(is_leaf: true) }
  scope :by_class,  ->(klass) { where(account_class: klass) }

  def full_label
    "#{code} — #{label_fr}"
  end
end

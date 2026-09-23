class Accounting::IntracomListingLine < ApplicationRecord
  self.table_name = "accounting_intracom_listing_lines"

  acts_as_tenant :entity

  belongs_to :intracom_listing, class_name: "Accounting::IntracomListing", inverse_of: :lines
  belongs_to :partner,          class_name: "Accounting::Partner"

  validates :amount, presence: true
  validates :code,   inclusion: { in: %w[L S] }
end

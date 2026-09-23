class Accounting::IntracomListing < ApplicationRecord
  self.table_name = "accounting_intracom_listings"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :intracom_listings ] }

  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear"
  has_many   :lines, class_name: "Accounting::IntracomListingLine",
             foreign_key: :intracom_listing_id, dependent: :destroy, inverse_of: :intracom_listing

  enum :status, { draft: 0, submitted: 1 }

  autofilter_column :period_start, sql: "accounting_intracom_listings.period_start", type: :date
  autofilter_column :status,       sql: "accounting_intracom_listings.status", type: :enum

  validates :period_start, presence: true
  validates :period_end,   presence: true

  validate :period_end_after_period_start

  def total_amount
    lines.sum(:amount)
  end

  private

  def period_end_after_period_start
    return unless period_start && period_end
    errors.add(:period_end, :greater_than, count: period_start) if period_end < period_start
  end

  def self.filter_by(q)
    matching(status: q[:status], fiscal_year_id: q[:fiscal_year_id])
  end
end

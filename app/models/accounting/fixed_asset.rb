# Tracks a capital good's initial VAT deduction for the Belgian multi-year review period
# (5 years for movable assets, 15 for immovable) — see Accounting::Actions::ReviewFixedAssetVat.
class Accounting::FixedAsset < ApplicationRecord
  self.table_name = "accounting_fixed_assets"

  acts_as_tenant :entity

  REVIEW_PERIOD_YEARS = { movable: 5, immovable: 15 }.freeze

  enum :asset_category, { movable: 0, immovable: 1 }

  belongs_to :invoice_line, class_name: "Accounting::InvoiceLine", optional: true

  validates :description,      presence: true
  validates :acquisition_date, presence: true
  validates :vat_amount_initial, presence: true, numericality: { greater_than: 0 }
  validates :prorata_at_acquisition,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def review_period_years
    REVIEW_PERIOD_YEARS.fetch(asset_category.to_sym)
  end

  def annual_tranche
    (vat_amount_initial / review_period_years).round(2)
  end

  def acquisition_year
    acquisition_date.year
  end

  def review_end_year
    acquisition_year + review_period_years - 1
  end

  def under_review?(year)
    return false if year < acquisition_year || year > review_end_year
    disposed_on.nil? || year <= disposed_on.year
  end

  # Number of review years remaining from `year` (inclusive) through the end of the period.
  def remaining_review_years(year)
    [ review_end_year - year + 1, 0 ].max
  end
end

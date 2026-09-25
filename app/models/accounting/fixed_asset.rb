# A capital good. Tracks its initial VAT deduction for the Belgian multi-year review period
# (5 years for movable assets, 15 for immovable) — see Accounting::Actions::ReviewFixedAssetVat —
# and, once acquisition_value, useful_life_years and asset_account are set, its straight-line
# depreciation, prorated by month from the month the asset is put in service.
class Accounting::FixedAsset < ApplicationRecord
  self.table_name = "accounting_fixed_assets"

  acts_as_tenant :entity

  REVIEW_PERIOD_YEARS = { movable: 5, immovable: 15 }.freeze

  # Asset account prefix => [depreciation expense account, accumulated depreciation account].
  DEPRECIATION_ACCOUNTS = {
    "21" => %w[630100 219000],
    "22" => %w[630200 229000],
    "23" => %w[630200 239000],
    "24" => %w[630200 249000]
  }.freeze
  NON_DEPRECIABLE_ACCOUNTS = %w[220100].freeze # land

  enum :asset_category, { movable: 0, immovable: 1 }
  enum :depreciation_method, { linear: 0 }, prefix: :depreciation_method

  belongs_to :invoice_line, class_name: "Accounting::InvoiceLine", optional: true
  belongs_to :asset_account, class_name: "Accounting::Account", optional: true
  belongs_to :disposal_journal_entry, class_name: "Accounting::JournalEntry", optional: true
  has_many   :depreciation_entries, class_name: "Accounting::DepreciationEntry", foreign_key: :fixed_asset_id,
                                    inverse_of: :fixed_asset, dependent: :restrict_with_error

  validates :description,      presence: true
  validates :acquisition_date, presence: true
  validates :vat_amount_initial, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :prorata_at_acquisition,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  validates :acquisition_value, numericality: { greater_than: 0 }, allow_nil: true
  validates :useful_life_years, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :residual_value,    numericality: { greater_than_or_equal_to: 0 }
  validates :asset_account, :useful_life_years, presence: true, if: -> { acquisition_value.present? }
  validate  :residual_within_acquisition_value
  validate  :asset_account_depreciable
  validate  :disposal_only_through_dispose

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

  # Accounts an asset can be booked on: 21x to 24x, land excluded.
  def self.asset_accounts
    Accounting::Account.active.leaf.where("code ~ '^2[1-4]'").where.not(code: NON_DEPRECIABLE_ACCOUNTS).order(:code)
  end

  def disposed? = disposed_on.present?

  def depreciable?
    acquisition_value.present? && useful_life_years.present? && asset_account.present?
  end

  def depreciation_base = acquisition_value - residual_value

  # { expense: "630200", accumulated: "249000" } for the asset account's class.
  def depreciation_accounts
    expense, accumulated = DEPRECIATION_ACCOUNTS.fetch(asset_account.code[0, 2])
    { expense: expense, accumulated: accumulated }
  end

  # Depreciation booked over a fiscal year. The cumulative amounts are rounded, not the yearly ones,
  # so the plan always sums to the depreciable base exactly.
  def depreciation_for(fiscal_year) = depreciation_between(fiscal_year.start_date, fiscal_year.end_date)

  # One row per calendar year until fully depreciated (or disposed). Display only: postings follow the fiscal years.
  def depreciation_plan
    return [] unless depreciable?

    (start_month_index / 12..last_month_index / 12).map do |year|
      amount = depreciation_between(Date.new(year, 1, 1), Date.new(year, 12, 31))
      accumulated = cumulative_depreciation(months_elapsed(year * 12 + 11))
      { year: year, amount: amount, accumulated: accumulated, net_book_value: acquisition_value - accumulated }
    end
  end

  private

  def depreciation_between(from, to)
    return BigDecimal("0") unless depreciable?

    cumulative_depreciation(months_elapsed(month_index(to))) - cumulative_depreciation(months_elapsed(month_index(from) - 1))
  end

  def month_index(date) = date.year * 12 + date.month - 1

  def start_month_index = month_index(in_service_date || acquisition_date)

  def life_months = useful_life_years * 12

  # Last month of the plan: the end of the useful life, or the disposal month if earlier.
  def last_month_index
    [ start_month_index + life_months - 1, (month_index(disposed_on) if disposed_on) ].compact.min
  end

  # Months depreciated up to and including month `index`.
  def months_elapsed(index) = (([ index, last_month_index ].min - start_month_index) + 1).clamp(0, life_months)

  def cumulative_depreciation(months) = (depreciation_base * months / life_months).round(2)

  def residual_within_acquisition_value
    return if acquisition_value.blank? || residual_value.blank?

    errors.add(:residual_value, "cannot exceed the acquisition value") if residual_value > acquisition_value
  end

  # For an asset that depreciates, the disposal date is only set together with its exit entry
  # (Accounting::DisposeFixedAsset): typing it freely would skip the accounting.
  def disposal_only_through_dispose
    return unless depreciable? && disposed_on_changed? && !disposal_journal_entry_id_changed?

    errors.add(:disposed_on, "cannot be changed here: use Dispose")
  end

  def asset_account_depreciable
    return if asset_account.blank?

    code = asset_account.code
    return if DEPRECIATION_ACCOUNTS.key?(code[0, 2]) && NON_DEPRECIABLE_ACCOUNTS.exclude?(code)

    errors.add(:asset_account, "is not a depreciable fixed asset account")
  end
end

# One year's VAT review for a single capital good (Accounting::FixedAsset), per the Belgian
# multi-year revision mechanism: 1/5 or 1/15 of the initial VAT is reconsidered each year the
# asset stays under review, based on the gap between the prorata at acquisition and the
# entity's final prorata for that year.
#
# A disposal within the review period is a separate, mandatory rule: all remaining review
# years are regularized at once, as if the asset had been used for taxed activity (100%)
# from the disposal onward — no 10-point tolerance applies to this case.
class Accounting::Actions::ReviewFixedAssetVat
  THRESHOLD_POINTS = 10

  def self.call(fixed_asset:, fiscal_year:, final_prorata_rate:)
    ctx = LightService::Context.make(journal_entry: nil)
    year = fiscal_year.year
    return ctx unless fixed_asset.under_review?(year)

    adjustment = fixed_asset.disposed_on&.year == year ? disposal_adjustment(fixed_asset, year) : annual_adjustment(fixed_asset, final_prorata_rate)

    ctx[:journal_entry] = post_adjustment(fixed_asset, fiscal_year, adjustment) unless adjustment.nil? || adjustment.zero?
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.annual_adjustment(fixed_asset, final_prorata_rate)
    gap = final_prorata_rate - fixed_asset.prorata_at_acquisition
    return nil if gap.abs <= THRESHOLD_POINTS
    (fixed_asset.annual_tranche * gap / 100).round(2)
  end

  def self.disposal_adjustment(fixed_asset, year)
    remaining_years = fixed_asset.remaining_review_years(year)
    gap = 100 - fixed_asset.prorata_at_acquisition
    (fixed_asset.annual_tranche * remaining_years * gap / 100).round(2)
  end

  def self.post_adjustment(fixed_asset, fiscal_year, adjustment)
    journal                = Accounting::Journal.active.find_by!(journal_type: :misc)
    deductible_account     = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_DEDUCTIBLE)
    non_deductible_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_NON_DEDUCTIBLE)
    amount = adjustment.abs

    entry = Accounting::JournalEntry.new(
      journal:      journal,
      fiscal_year:  fiscal_year,
      entry_date:   fiscal_year.end_date,
      reference:    "VAT-ASSET-#{fixed_asset.id}-#{fiscal_year.year}",
      description:  "VAT review for #{fixed_asset.description} (#{fiscal_year.year})",
      status:       :draft
    )
    entry.save!

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

      if adjustment.positive? # additional deduction recovered — grid 62
        create_line(entry, deductible_account, debit: amount, credit: 0, vat_code: 62, vat_amount: amount)
        create_line(entry, non_deductible_account, debit: 0, credit: amount)
      else # deduction to reverse — grid 61
        create_line(entry, non_deductible_account, debit: amount, credit: 0)
        create_line(entry, deductible_account, debit: 0, credit: amount, vat_code: 61, vat_amount: amount)
      end

      entry.post!
    end

    entry
  end

  def self.create_line(entry, account, debit:, credit:, vat_code: nil, vat_amount: nil)
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: account, debit: debit, credit: credit,
      label: "Fixed asset VAT review", vat_code: vat_code, vat_amount: vat_amount
    )
  end

  private_class_method :annual_adjustment, :disposal_adjustment, :post_adjustment, :create_line
end

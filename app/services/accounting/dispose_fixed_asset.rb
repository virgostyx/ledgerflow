# Disposes of a depreciable fixed asset (sold or scrapped) on a given date, all or nothing:
# 1. books the depreciation of the disposal year up to the disposal month, dated at the disposal date;
# 2. takes the asset off the books: debit the accumulated depreciation and the net book value (660100), credit the
#    asset account at cost. The sale price is not booked here: issue a customer invoice with a line on 760100, so the
#    profit or loss shows as 760100 - 660100 (gross presentation).
class Accounting::DisposeFixedAsset
  def self.call(fixed_asset:, disposed_on:)
    ctx = LightService::Context.make(fixed_asset: fixed_asset, journal_entry: nil, book_value: nil)
    fiscal_year = Accounting::FiscalYear.where("start_date <= :date AND end_date >= :date", date: disposed_on).first
    error = refusal_for(fixed_asset, disposed_on, fiscal_year)
    return ctx.tap { |c| c.fail!(error) } if error

    journal = Accounting::Journal.active.find_by(journal_type: :misc)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.fixed_assets.errors.no_misc_journal")) } unless journal

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      fixed_asset.disposed_on = disposed_on # depreciation stops at the disposal month
      amount = fixed_asset.depreciation_for(fiscal_year)
      Accounting::PostDepreciation.post(fixed_asset, amount, fiscal_year, journal) if amount.positive?
      ctx[:journal_entry] = post_exit(fixed_asset, fiscal_year, journal)
      ctx[:book_value] = fixed_asset.acquisition_value - fixed_asset.depreciation_entries.sum(:amount)
      fixed_asset.update!(disposal_journal_entry: ctx[:journal_entry])
    end
    ctx
  rescue StandardError => e
    fixed_asset.restore_attributes(%i[disposed_on disposal_journal_entry_id])
    ctx.tap { |c| c.fail!("Error: #{e.message}") }
  end

  def self.refusal_for(asset, date, fiscal_year)
    key = if !asset.depreciable?                                           then :not_depreciable
    elsif asset.disposed?                                                  then :already_disposed
    elsif date < (asset.in_service_date || asset.acquisition_date)         then :before_in_service
    elsif fiscal_year.nil?                                                 then :no_fiscal_year
    elsif fiscal_year.closed?                                              then :fiscal_year_closed
    end
    return I18n.t("accounting.fixed_assets.errors.#{key}") if key

    behind = earlier_year_pending(asset, fiscal_year)
    return I18n.t("accounting.fixed_assets.errors.earlier_year_pending", year: behind.year) if behind

    I18n.t("accounting.fixed_assets.errors.year_already_depreciated", year: fiscal_year.year) if asset.depreciation_entries.exists?(fiscal_year: fiscal_year)
  end

  # The first earlier fiscal year whose depreciation for this asset has not been posted.
  def self.earlier_year_pending(asset, fiscal_year)
    Accounting::FiscalYear.where("end_date < ?", fiscal_year.start_date).order(:year).find do |year|
      Accounting::PostDepreciation.pending(year).any? { |pending_asset, _| pending_asset.id == asset.id }
    end
  end

  def self.post_exit(asset, fiscal_year, journal)
    accumulated = asset.depreciation_entries.sum(:amount)
    book_value  = asset.acquisition_value - accumulated
    entry = Accounting::JournalEntry.create!(
      journal: journal, fiscal_year: fiscal_year, entry_date: asset.disposed_on, status: :draft,
      reference: "DISPOSAL-ASSET-#{asset.id}", description: "Disposal: #{asset.description}"
    )
    line = ->(account, **amounts) { Accounting::JournalEntryLine.create!(journal_entry: entry, account: account, label: "Disposal #{asset.description}", debit: 0, credit: 0, **amounts) }
    accounts = asset.depreciation_accounts
    line.call(Accounting::Account.find_by!(code: accounts[:accumulated]), debit: accumulated) if accumulated.positive?
    line.call(Accounting::Account.find_by!(code: Accounting::AccountCodes::ASSET_DISPOSAL), debit: book_value) if book_value.positive?
    line.call(asset.asset_account, credit: asset.acquisition_value)
    entry.post!
    entry
  end

  private_class_method :refusal_for, :earlier_year_pending, :post_exit
end

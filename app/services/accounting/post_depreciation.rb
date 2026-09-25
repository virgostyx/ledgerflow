# Books the depreciation of a fiscal year: one miscellaneous-journal entry per depreciable fixed asset (debit the
# depreciation expense, credit the accumulated depreciation), recorded in an Accounting::DepreciationEntry so that
# running it again only posts what is still missing. All or nothing.
class Accounting::PostDepreciation
  def self.call(fiscal_year:)
    ctx = LightService::Context.make(fiscal_year: fiscal_year, entries: [], total: BigDecimal("0"))
    return ctx.tap { |c| c.fail!(I18n.t("accounting.fixed_assets.errors.fiscal_year_closed")) } if fiscal_year.closed?

    journal = Accounting::Journal.active.find_by(journal_type: :misc)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.fixed_assets.errors.no_misc_journal")) } unless journal

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      pending(fiscal_year).each { |asset, amount| ctx[:entries] << post(asset, amount, fiscal_year, journal) }
    end
    ctx[:total] = ctx[:entries].sum(&:amount)
    ctx
  rescue StandardError => e
    ctx[:entries] = []
    ctx.tap { |c| c.fail!("Error: #{e.message}") }
  end

  # [[asset, amount], ...] for the assets that still have depreciation to book for the year.
  # Public: closing a fiscal year checks it is empty.
  def self.pending(fiscal_year)
    done = Accounting::DepreciationEntry.where(fiscal_year: fiscal_year).pluck(:fixed_asset_id)
    Accounting::FixedAsset.includes(:asset_account).where.not(id: done).order(:id).filter_map do |asset|
      amount = asset.depreciation_for(fiscal_year)
      [ asset, amount ] if asset.depreciable? && amount.positive?
    end
  end

  def self.post(asset, amount, fiscal_year, journal)
    codes   = asset.depreciation_accounts
    expense = Accounting::Account.find_by!(code: codes[:expense])
    contra  = Accounting::Account.find_by!(code: codes[:accumulated])

    entry = Accounting::JournalEntry.create!(
      journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.end_date, status: :draft,
      reference: "DEP-ASSET-#{asset.id}-#{fiscal_year.year}",
      description: "Depreciation #{fiscal_year.year}: #{asset.description}"
    )
    line = { journal_entry: entry, label: "Depreciation #{asset.description}" }
    Accounting::JournalEntryLine.create!(**line, account: expense, debit: amount, credit: 0)
    Accounting::JournalEntryLine.create!(**line, account: contra, debit: 0, credit: amount)
    entry.post!

    Accounting::DepreciationEntry.create!(fixed_asset: asset, fiscal_year: fiscal_year, journal_entry: entry, amount: amount)
  end

  private_class_method :post
end

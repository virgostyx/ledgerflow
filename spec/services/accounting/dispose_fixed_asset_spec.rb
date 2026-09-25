require 'rails_helper'

RSpec.describe Accounting::DisposeFixedAsset, type: :service do
  include_context 'with entity'

  let!(:fy2026) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open) }
  let!(:misc_journal) { create(:journal, journal_type: :misc) }
  let!(:asset_account)       { create(:account, code: '240200', label_fr: 'Matériel informatique', account_class: 2, account_type: :asset, normal_balance: :debit) }
  let!(:accumulated_account) { create(:account, code: '249000', label_fr: 'Amortissements mobilier', account_class: 2, account_type: :asset, normal_balance: :credit) }
  let!(:expense_account)     { create(:account, code: '630200', label_fr: 'Amortissements', account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:disposal_account)    { create(:account, code: '660100', label_fr: 'Moins-values sur réalisations', account_class: 6, account_type: :expense, normal_balance: :debit) }

  # 12 000 EUR, 5 years, 200 per month from October 2026.
  let!(:asset) { create(:fixed_asset, :depreciable, description: 'Office laptops') }

  # Closes 2026 after its depreciation is posted, and opens 2027 (only one open year at a time).
  def move_to_2027
    Accounting::PostDepreciation.call(fiscal_year: fy2026)
    fy2026.update!(status: :closed, closed_at: Time.current)
    create(:fiscal_year, year: 2027, start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 12, 31), status: :open)
  end

  def line(entry, account) = entry.lines.find_by(account: account)

  # An earlier, closed year in which the asset was already depreciated.
  def depreciated_in_2025(amount)
    fy2025 = create(:fiscal_year, year: 2025, start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31), status: :closed, closed_at: Time.current)
    create(:depreciation_entry, fixed_asset: asset, fiscal_year: fy2025, amount: amount)
  end

  describe 'a disposal during the year' do
    let!(:fy2027) { move_to_2027 }
    subject(:result) { described_class.call(fixed_asset: asset, disposed_on: Date.new(2027, 3, 20)) }

    it 'takes the asset off the books at its net book value' do
      expect(result).to be_success
      entry = result[:journal_entry]

      expect(entry).to be_posted
      expect(entry).to have_attributes(journal: misc_journal, fiscal_year: fy2027, entry_date: Date.new(2027, 3, 20),
                                       reference: "DISPOSAL-ASSET-#{asset.id}")
      # October 2026 to March 2027: 6 months = 1 200 depreciated, 10 800 left.
      expect(line(entry, accumulated_account)).to have_attributes(debit: BigDecimal('1200.00'), credit: BigDecimal('0'))
      expect(line(entry, disposal_account)).to have_attributes(debit: BigDecimal('10800.00'), credit: BigDecimal('0'))
      expect(line(entry, asset_account)).to have_attributes(debit: BigDecimal('0'), credit: BigDecimal('12000.00'))
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it 'first books the depreciation of the disposal year, dated at the disposal date, through the disposal month' do
      result

      entry = asset.depreciation_entries.find_by(fiscal_year: fy2027)
      expect(entry.amount).to eq(BigDecimal('600.00')) # January to March
      expect(entry.journal_entry.entry_date).to eq(Date.new(2027, 3, 20))
    end

    it 'reports the net book value written off' do
      expect(result[:book_value]).to eq(BigDecimal('10800.00'))
    end

    it 'records the disposal on the asset' do
      result

      expect(asset.reload).to have_attributes(disposed_on: Date.new(2027, 3, 20), disposal_journal_entry: result[:journal_entry])
    end

    it 'cannot be done twice' do
      result
      again = described_class.call(fixed_asset: asset.reload, disposed_on: Date.new(2027, 4, 1))

      expect(again).to be_failure
      expect(again.message).to be_present
    end

    it 'leaves no depreciation to book for the year once disposed (the year end run posts nothing more)' do
      result
      expect(Accounting::PostDepreciation.call(fiscal_year: fy2027)[:entries]).to be_empty
    end
  end

  describe 'other situations' do
    it 'disposes in the same year, booking the depreciation of the year up to the disposal month' do
      result = described_class.call(fixed_asset: asset, disposed_on: Date.new(2026, 12, 5))

      expect(result).to be_success
      expect(asset.depreciation_entries.sole.amount).to eq(BigDecimal('600.00')) # October to December
      expect(line(result[:journal_entry], disposal_account).debit).to eq(BigDecimal('11400.00'))
    end

    it 'has no loss line for a fully depreciated asset' do
      asset.update_columns(acquisition_date: Date.new(2018, 1, 1), in_service_date: Date.new(2018, 1, 1))
      depreciated_in_2025('12000.00')

      result = described_class.call(fixed_asset: asset, disposed_on: Date.new(2026, 6, 30))

      expect(result).to be_success
      expect(line(result[:journal_entry], disposal_account)).to be_nil
      expect(line(result[:journal_entry], accumulated_account).debit).to eq(BigDecimal('12000.00'))
      expect(line(result[:journal_entry], asset_account).credit).to eq(BigDecimal('12000.00'))
    end

    it 'keeps the residual value in the net book value' do
      asset.update!(residual_value: 2000, acquisition_date: Date.new(2018, 1, 1), in_service_date: Date.new(2018, 1, 1))
      depreciated_in_2025('10000.00')

      result = described_class.call(fixed_asset: asset, disposed_on: Date.new(2026, 6, 30))

      expect(line(result[:journal_entry], disposal_account).debit).to eq(BigDecimal('2000.00'))
    end

    it 'accepts a fiscal year in pre-closing' do
      fy2026.update!(status: :pre_closing)
      expect(described_class.call(fixed_asset: asset, disposed_on: Date.new(2026, 12, 5))).to be_success
    end
  end

  describe 'refusals' do
    def refused(**args)
      result = described_class.call(fixed_asset: asset, disposed_on: Date.new(2026, 12, 5), **args)
      expect(result).to be_failure
      expect(result.message).to be_present
      expect([ Accounting::JournalEntry.count, Accounting::DepreciationEntry.count, asset.reload.disposed_on ]).to eq([ 0, 0, nil ])
      result
    end

    it 'refuses an asset that does not depreciate' do
      plain = create(:fixed_asset)
      result = described_class.call(fixed_asset: plain, disposed_on: Date.new(2026, 12, 5))

      expect(result).to be_failure
      expect(Accounting::JournalEntry.count).to eq(0)
    end

    it 'refuses a date before the asset is in service' do
      refused(disposed_on: Date.new(2026, 9, 30))
    end

    it 'refuses a date outside every fiscal year' do
      refused(disposed_on: Date.new(2031, 1, 5))
    end

    it 'refuses a closed fiscal year' do
      fy2026.update!(status: :closed, closed_at: Time.current)
      refused
    end

    it 'refuses when the depreciation of an earlier year has not been posted, naming the year' do
      fy2026.update!(status: :closed, closed_at: Time.current)
      create(:fiscal_year, year: 2027, start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 12, 31), status: :open)

      result = described_class.call(fixed_asset: asset, disposed_on: Date.new(2027, 3, 20))

      expect(result).to be_failure
      expect(result.message).to include('2026')
      expect(Accounting::JournalEntry.count).to eq(0)
    end

    it 'refuses when the year depreciation was already booked for the whole year' do
      Accounting::PostDepreciation.call(fiscal_year: fy2026)
      journal_entries = Accounting::JournalEntry.count

      result = described_class.call(fixed_asset: asset, disposed_on: Date.new(2026, 12, 5))

      expect(result).to be_failure
      expect(Accounting::JournalEntry.count).to eq(journal_entries)
      expect(asset.reload.disposed_on).to be_nil
    end

    it 'fails without a miscellaneous journal' do
      misc_journal.update!(active: false)
      refused
    end

    it 'is all or nothing: a missing account cancels the depreciation entry too' do
      disposal_account.destroy!
      refused
    end
  end
end

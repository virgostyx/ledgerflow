require 'rails_helper'

RSpec.describe Accounting::PostDepreciation, type: :service do
  include_context 'with entity'

  let!(:fy2026) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open) }
  let!(:misc_journal) { create(:journal, journal_type: :misc) }
  let!(:expense_account)     { create(:account, code: '630200', label_fr: 'Amortissements corporelles', account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:accumulated_account) { create(:account, code: '249000', label_fr: 'Amortissements mobilier', account_class: 2, account_type: :asset, normal_balance: :credit) }

  # 12 000 EUR, 5 years, from October 2026: 600 in 2026, 2 400 in 2027.
  def asset(**attrs) = create(:fixed_asset, :depreciable, **attrs)

  it 'posts one balanced entry per asset: debit the expense, credit the accumulated depreciation' do
    a = asset
    result = described_class.call(fiscal_year: fy2026)

    expect(result).to be_success
    entry = result[:entries].sole.journal_entry
    expect(entry).to be_posted
    expect(entry).to have_attributes(journal: misc_journal, fiscal_year: fy2026, entry_date: Date.new(2026, 12, 31),
                                     reference: "DEP-ASSET-#{a.id}-2026")
    expect(entry.lines.find_by(account: expense_account)).to have_attributes(debit: BigDecimal('600.00'), credit: BigDecimal('0'))
    expect(entry.lines.find_by(account: accumulated_account)).to have_attributes(debit: BigDecimal('0'), credit: BigDecimal('600.00'))
    expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
  end

  it 'records the depreciation entry with its amount and reports the total' do
    a = asset
    result = described_class.call(fiscal_year: fy2026)

    expect(result[:entries].sole).to have_attributes(fixed_asset: a, fiscal_year: fy2026, amount: BigDecimal('600.00'))
    expect(result[:total]).to eq(BigDecimal('600.00'))
  end

  it 'posts one entry for each depreciable asset' do
    asset
    asset(description: 'Second laptop')
    result = described_class.call(fiscal_year: fy2026)

    expect(result[:entries].size).to eq(2)
    expect(result[:total]).to eq(BigDecimal('1200.00'))
  end

  it 'is idempotent: a second run posts nothing new' do
    asset
    described_class.call(fiscal_year: fy2026)

    expect { @second = described_class.call(fiscal_year: fy2026) }
      .not_to change { [ Accounting::DepreciationEntry.count, Accounting::JournalEntry.count ] }
    expect(@second).to be_success
    expect(@second[:entries]).to be_empty
  end

  it 'skips assets that are not set up for depreciation' do
    create(:fixed_asset)
    result = described_class.call(fiscal_year: fy2026)

    expect(result).to be_success
    expect(result[:entries]).to be_empty
  end

  it 'skips assets with nothing to depreciate in the year' do
    asset(in_service_date: Date.new(2028, 1, 1), acquisition_date: Date.new(2028, 1, 1)) # not yet in service
    asset(in_service_date: Date.new(2018, 1, 1), acquisition_date: Date.new(2018, 1, 1)) # fully depreciated by 2022

    expect(described_class.call(fiscal_year: fy2026)[:entries]).to be_empty
  end

  it 'posts the next year for an asset already depreciated the year before' do
    asset
    described_class.call(fiscal_year: fy2026)
    fy2026.update!(status: :closed, closed_at: Time.current)
    fy2027 = create(:fiscal_year, year: 2027, start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 12, 31), status: :open)

    result = described_class.call(fiscal_year: fy2027)

    expect(result[:entries].sole.amount).to eq(BigDecimal('2400.00'))
  end

  it 'accepts a fiscal year in pre-closing' do
    asset
    fy2026.update!(status: :pre_closing)

    expect(described_class.call(fiscal_year: fy2026)).to be_success
  end

  it 'refuses a closed fiscal year and posts nothing' do
    asset
    fy2026.update!(status: :closed, closed_at: Time.current)

    result = described_class.call(fiscal_year: fy2026)

    expect(result).to be_failure
    expect(result.message).to be_present
    expect(Accounting::DepreciationEntry.count).to eq(0)
  end

  it 'fails cleanly when there is no miscellaneous journal' do
    asset
    misc_journal.update!(active: false)

    result = described_class.call(fiscal_year: fy2026)

    expect(result).to be_failure
    expect(Accounting::JournalEntry.count).to eq(0)
  end

  it 'dates the depreciation of the disposal year at the disposal date, through the disposal month' do
    a = asset(acquisition_date: Date.new(2026, 1, 1), in_service_date: Date.new(2026, 1, 1)) # 200 per month
    a.update_columns(disposed_on: Date.new(2026, 4, 20))

    result = described_class.call(fiscal_year: fy2026)

    entry = result[:entries].sole
    expect(entry.amount).to eq(BigDecimal('800.00')) # January to April
    expect(entry.journal_entry.entry_date).to eq(Date.new(2026, 4, 20))
  end

  it 'keeps the fiscal year end date for an asset disposed in another year' do
    a = asset(acquisition_date: Date.new(2026, 1, 1), in_service_date: Date.new(2026, 1, 1))
    a.update_columns(disposed_on: Date.new(2027, 4, 20))

    expect(described_class.call(fiscal_year: fy2026)[:entries].sole.journal_entry.entry_date).to eq(Date.new(2026, 12, 31))
  end

  it 'is all or nothing: one asset that cannot be posted cancels the others' do
    asset
    intangible = Accounting::Account.create!(code: '210200', label_fr: 'Logiciels', account_class: 2, account_type: :asset, normal_balance: :debit) # no 219000
    asset(description: 'Software licence', asset_account: intangible)

    result = described_class.call(fiscal_year: fy2026)

    expect(result).to be_failure
    expect(Accounting::DepreciationEntry.count).to eq(0)
    expect(Accounting::JournalEntry.count).to eq(0)
  end
end

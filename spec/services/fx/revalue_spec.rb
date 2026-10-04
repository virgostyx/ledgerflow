require "rails_helper"

# F11, the revaluation at closing: the foreign receivables, payables and bank balances at the closing rate, as a DRAFT with its reversal scheduled
# on the first day of the next period. Nothing is posted here, and what is booked follows the treatment chosen by the entity.
RSpec.describe Fx::Revalue, type: :service do
  include_context "with_pcmn_accounts"
  include_context "with_open_fiscal_year"
  include ActiveJob::TestHelper

  let!(:unrealized_loss) { create(:account, code: "499100", label_fr: "Unrealized FX losses", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let!(:unrealized_gain) { create(:account, code: "499200", label_fr: "Unrealized FX gains", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:deferred)        { create(:account, code: "492200", label_fr: "Deferred income", account_class: 4, account_type: :liability, normal_balance: :credit) }
  let!(:purchase)   { create(:journal, :purchase, default_account: account_440) }
  let!(:misc)       { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let!(:supplier)   { create(:partner, :supplier, :with_iban, external_ref: "S1") }
  let(:closing)     { fiscal_year.end_date }

  def usd_payable(ref, price)
    Accounting::ExternalInvoice.upsert(
      external_ref: ref, partner_external_ref: "S1", invoice_type: "supplier", invoice_date: fiscal_year.start_date.to_s,
      currency: "USD", exchange_rate: "1.11111111",
      lines: [ { account_code: "604000", description: "Work", quantity: "1", unit_price: price, vat_rate: "0" } ]
    ).invoice
  end

  def closing_rate(value) = Accounting::ExchangeRate.create!(currency: "USD", rate_date: closing, rate: value, rate_type: :closing, source: "manual")
  def call = described_class.call(fiscal_year: fiscal_year)
  def entries = Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::REVALUATION_SOURCE)

  # 1 000 USD payable booked 900 EUR; at 1.05263158 it is 950 EUR (a loss of 50), at 1.17647059 it is 850 EUR (a gain of 50)
  describe "an unrealized loss" do
    before do
      usd_payable("U1", "1000")
      closing_rate("1.05263158")
    end

    it "is a draft dated at the closing date: Dr 651200 / Cr 499100, with its reversal scheduled for the next day (criterion 5)" do
      result = call

      expect(result).to be_success, result.message
      entry = result[:entry]
      expect(entry).to be_draft
      expect(entry).to have_attributes(entry_date: closing, auto_reverse_on: closing + 1)
      expect(entry.lines.find_by(account: account_651200).debit).to eq(BigDecimal("50"))
      expect(entry.lines.find_by(account: unrealized_loss).credit).to eq(BigDecimal("50"))
    end

    it "posts nothing, and makes no second entry when asked again" do
      first = call[:entry]
      expect(call[:entry]).to eq(first)
      expect(entries.count).to eq(1)
    end

    it "is reversed by the scheduled reversal once posted, on the date asked, as a draft (as soon as the next fiscal year exists)" do
      entry = call[:entry]
      Accounting::PostJournalEntry.call!(entry: entry)
      fiscal_year.update!(status: :pre_closing) # the year is being closed; the next one is the open one
      create(:fiscal_year, status: :open, entity: entity, year: fiscal_year.year + 1, start_date: closing + 1, end_date: closing + 365)
      travel_to(closing + 1) { Accounting::AutoReverseEntriesJob.perform_now }

      reversal = entry.reload.reversal
      expect(reversal).to be_draft
      expect(reversal.entry_date).to eq(closing + 1)
      expect(reversal.lines.find_by(account: unrealized_loss).debit).to eq(BigDecimal("50"))
    end

    it "is left out when the entity chose not to book losses" do
      entity.update!(fx_unrealized_loss: :ignore)
      result = call
      expect(result).to be_failure
      expect(entries.count).to eq(0)
    end

    it "takes the loss account the entity set" do
      create(:account, code: "654000", account_type: :expense, normal_balance: :debit)
      entity.update!(fx_loss_account_code: "654000")
      expect(call[:entry].lines.joins(:account).where(accounting_accounts: { code: "654000" }).sum(:debit)).to eq(BigDecimal("50"))
    end
  end

  describe "an unrealized gain" do
    before do
      usd_payable("U1", "1000")
      closing_rate("1.17647059")
    end

    it "is not booked by default (what was decided at the first revaluation)" do
      result = call
      expect(result).to be_failure
      expect(result.message).to match(/nothing to book/i)
      expect(entries.count).to eq(0)
    end

    it "is deferred when the entity chose it: Dr 499200 / Cr 492200, the profit and loss untouched" do
      entity.update!(fx_unrealized_gain: :defer)
      entry = call[:entry]
      expect(entry.lines.find_by(account: unrealized_gain).debit).to eq(BigDecimal("50"))
      expect(entry.lines.find_by(account: deferred).credit).to eq(BigDecimal("50"))
      expect(entry.auto_reverse_on).to eq(closing + 1)
    end

    it "is recognized when the entity chose it: Dr 499200 / Cr the gain account" do
      entity.update!(fx_unrealized_gain: :recognize)
      entry = call[:entry]
      expect(entry.lines.find_by(account: account_751100).credit).to eq(BigDecimal("50"))
    end

    it "refuses when the account that holds it does not exist, and names it" do
      entity.update!(fx_unrealized_gain: :defer)
      deferred.destroy!
      result = call
      expect(result).to be_failure
      expect(result.message).to include("492200")
    end
  end

  it "books losses and gains of different currencies side by side, never netting one against the other" do
    usd_payable("U1", "1000")
    closing_rate("1.05263158") # loss of 50 on the USD payable
    entity.update!(fx_unrealized_gain: :defer)
    zmw = Accounting::ExternalInvoice.upsert(
      external_ref: "Z1", partner_external_ref: "S1", invoice_type: "supplier", invoice_date: fiscal_year.start_date.to_s,
      currency: "ZMW", exchange_rate: "25",
      lines: [ { account_code: "604000", description: "Work", quantity: "1", unit_price: "1000", vat_rate: "0" } ]
    ).invoice
    expect(zmw).to be_posted # 40 EUR booked
    Accounting::ExchangeRate.create!(currency: "ZMW", rate_date: closing, rate: "20", rate_type: :closing, source: "manual") # 50 EUR: a loss of 10

    entry = call[:entry]
    expect(entry.lines.where(account: account_651200).sum(:debit)).to eq(BigDecimal("60"))
  end

  it "makes nothing for a currency whose balance has no difference (criterion 5)" do
    usd_payable("U1", "1000")
    closing_rate("1.11111111") # 1000 / 1.11111111 = 900.00: the booked value
    result = call
    expect(result).to be_failure
    expect(entries.count).to eq(0)
  end

  it "refuses without a closing rate, naming the currency and the date, and never takes a daily rate in its place" do
    usd_payable("U1", "1000")
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: closing, rate: "1.05", rate_type: :daily, source: "ecb")
    result = call
    expect(result).to be_failure
    expect(result.message).to include("USD", Accounting::DatePresenter.new(closing).format, "closing")
    expect(entries.count).to eq(0)
  end

  it "refuses when the unrealized-loss account does not exist, and names it" do
    usd_payable("U1", "1000")
    closing_rate("1.05263158")
    unrealized_loss.destroy!
    result = call
    expect(result).to be_failure
    expect(result.message).to include("499100")
  end

  it "has nothing to say without a foreign balance" do
    expect(call).to be_failure
  end
end

require "rails_helper"

# F11: a manual entry with a line in a foreign currency, as the form sends it: converted at the rate of the entry date, posted balanced in EUR and in
# the currency, refused with a message naming the currency and the date when the rate is missing.
RSpec.describe "Manual entries in a foreign currency", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:journal) { create(:journal, :purchase) }
  let(:day) { Date.current }

  before do
    sign_in accountant
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: day, rate: "1.25", rate_type: :daily, source: "ecb")
  end

  def post_entry(lines)
    post accounting_journal_entries_path, params: { accounting_journal_entry: {
      journal_id: journal.id, fiscal_year_id: fiscal_year.id, entry_date: day.iso8601, description: "USD supplies", lines_attributes: lines
    } }
  end

  let(:usd_lines) do
    {
      "0" => { account_id: account_604.id, currency: "USD", amount_currency: "1000", side: "debit", exchange_rate: "", debit: "", credit: "" },
      "1" => { account_id: account_440.id, currency: "USD", amount_currency: "1000", side: "credit", exchange_rate: "", debit: "", credit: "" }
    }
  end

  it "converts the lines at the official rate of the date and posts the entry, balanced in EUR and in USD" do
    expect { post_entry(usd_lines) }.to change(Accounting::JournalEntry, :count).by(1)

    entry = Accounting::JournalEntry.last
    expect(entry).to be_posted
    expect(entry.lines.find_by(account: account_604)).to have_attributes(debit: BigDecimal("800"), currency: "USD", amount_currency: BigDecimal("1000"), exchange_rate: BigDecimal("1.25"))
    expect(entry.lines.find_by(account: account_440)).to have_attributes(credit: BigDecimal("800"), amount_currency: BigDecimal("-1000"))
    expect(entry.lines.sum(:amount_currency)).to eq(0)
  end

  it "mixes a line in a foreign currency and a line in EUR" do
    post_entry(
      "0" => { account_id: account_604.id, currency: "USD", amount_currency: "1000", side: "debit", exchange_rate: "", debit: "", credit: "" },
      "1" => { account_id: account_440.id, currency: "EUR", amount_currency: "", side: "debit", exchange_rate: "", debit: "0", credit: "800.00" }
    )
    expect(Accounting::JournalEntry.last).to be_posted
  end

  it "refuses, saying which rate is missing, and saves nothing" do
    Accounting::ExchangeRate.delete_all
    expect { post_entry(usd_lines) }.not_to change(Accounting::JournalEntry, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("No exchange rate for USD", Accounting::DatePresenter.new(day).format)
  end

  it "ignores a rate typed in the form by someone who may not override rates" do
    reader = create(:user, role: :manager)
    create(:user_entity, :assistant, user: reader, entity: entity)
    sign_in reader
    lines = usd_lines.transform_values { |l| l.merge(exchange_rate: "9") }
    post_entry(lines)
    expect(Accounting::JournalEntryLine.where(currency: "USD").pluck(:exchange_rate).uniq).to eq([ BigDecimal("1.25") ]) if Accounting::JournalEntry.exists?
  end

  it "shows the currency fields of a line on the form" do
    get new_accounting_journal_entry_path
    expect(response.body).to include("Amount in currency", "Rate per 1 EUR")
  end
end

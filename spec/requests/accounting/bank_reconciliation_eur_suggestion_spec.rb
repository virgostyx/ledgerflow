require "rails_helper"

# A movement on a foreign account (kwacha): the bank knows no euro, the EUR amount is the conversion at the rate the entity's policy gives for the
# date of the movement. The reconciliation screen proposes it (editable); with no rate for that day it proposes nothing, and says so.
RSpec.describe "Bank reconciliation: the EUR amount of a foreign movement", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:bank_gl)      { create(:account, code: "550200", label_fr: "Banque ZMW", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:kwacha_account) { create(:bank_account, journal: bank_journal).tap { |b| b.update_columns(currency: "ZMW") } }
  let(:day) { Date.new(2026, 10, 20) }
  let!(:supplier_invoice) { create(:invoice, :supplier, :posted, fiscal_year: fiscal_year) }

  before do
    sign_in accountant
    create(:bank_transaction, bank_account: kwacha_account, amount: BigDecimal("-2750"), currency: "ZMW", transaction_date: day, reference: "ZMW-1")
  end

  def eur_fields = Nokogiri::HTML(response.body).css("input[name='bank_reconciliation[eur_amount]']")

  it "fills the EUR amount with the movement converted at the rate of its date, in both forms that ask for it" do
    Accounting::ExchangeRate.create!(currency: "ZMW", rate_date: day, rate: "27.5", rate_type: :daily, source: "inforeuro")

    get accounting_bank_reconciliation_path

    expect(eur_fields.size).to be >= 2
    expect(eur_fields.map { |f| f["value"] }.uniq).to eq([ "100.00" ])
  end

  it "leaves it empty and says there is no rate for that date" do
    get accounting_bank_reconciliation_path

    expect(eur_fields.map { |f| f["value"] }.compact).to be_empty
    expect(eur_fields.map { |f| f["placeholder"] }.uniq.join).to include("no ZMW rate")
  end

  describe "the suggestion of a payment that names the supplier's invoice" do
    before do
      supplier_invoice.update_columns(supplier_reference: "REF-ZMW-1", currency: "ZMW", total_incl_vat: BigDecimal("2750"))
      kwacha_account.transactions.destroy_all
      create(:bank_transaction, bank_account: kwacha_account, amount: BigDecimal("-2750"), currency: "ZMW", transaction_date: day, reference: "ZMW-2", description: "Transfer REF-ZMW-1")
    end

    it "says the euro value it will book, at the rate of the date" do
      Accounting::ExchangeRate.create!(currency: "ZMW", rate_date: day, rate: "27.5", rate_type: :daily, source: "inforeuro")

      get accounting_bank_reconciliation_path

      expect(response.body).to include("Suggested: supplier invoice REF-ZMW-1").and include("100.00 EUR at the rate of the date")
    end

    it "warns when no rate is known for that date" do
      get accounting_bank_reconciliation_path

      expect(response.body).to include("Suggested: supplier invoice REF-ZMW-1").and include("no ZMW rate for that date: the EUR amount is needed")
    end
  end
end

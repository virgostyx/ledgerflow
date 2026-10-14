require "rails_helper"

# B03a §"Données de référence versionnées": an account or a partner renamed keeps its former name in a view at an earlier instant. The versions are written by the
# database (a trigger), so nothing skips them, and never changed.
RSpec.describe "Versions of the reference data" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def versions_of(record) = Accounting::MasterDataVersion.where(record_type: record.class.name, record_id: record.id).order(:id)

  it "writes a version when an account or a partner is created, and when what is shown of it changes" do
    expect(versions_of(expense).count).to eq(1)
    expect(versions_of(expense).last.attrs).to include("label_fr" => "Services", "code" => "604000")

    expense.update!(label_fr: "Outside services")
    expect(versions_of(expense).count).to eq(2)
    expect(versions_of(expense).last.attrs).to include("label_fr" => "Outside services")

    partner = create(:partner, name: "Acme", vat_number: "BE0123456749")
    partner.update!(name: "Acme Ltd")
    expect(versions_of(partner).map { |v| v.attrs["name"] }).to eq([ "Acme", "Acme Ltd" ])
  end

  it "writes nothing when the change is not one that is shown (the cached balances move with every validation)" do
    expense.update_columns(balance_debit: 10, updated_at: Time.current)

    expect(versions_of(expense).count).to eq(1)
  end

  it "reads the version that held at an instant" do
    before_rename = instant
    expense.update!(label_fr: "Outside services")
    after_rename = instant

    expect(Accounting::MasterData.at(Accounting::Account, [ expense.id ], before_rename)[expense.id]).to include("label_fr" => "Services")
    expect(Accounting::MasterData.at(Accounting::Account, [ expense.id ], after_rename)[expense.id]).to include("label_fr" => "Outside services")
  end

  it "never changes a version" do
    version = versions_of(expense).first

    expect { version.update_columns(attrs: { "label_fr" => "forged" }) }.to raise_error(ActiveRecord::StatementInvalid, /never changed/)
    expect { ApplicationRecord.connection.execute("DELETE FROM accounting_master_data_versions WHERE id = #{version.id}") }.to raise_error(ActiveRecord::StatementInvalid)
  end

  describe "in the reports" do
    def post_entry(amount)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "M-#{SecureRandom.hex(3)}")
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
      entry.post!
      next_posting_instant
    end

    it "shows an account renamed since with the name it had" do
      post_entry(BigDecimal("10"))
      at = instant
      expense.update!(label_fr: "Outside services")

      past = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, known_at: at).call.find { |r| r.code == "604000" }
      now = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call.find { |r| r.code == "604000" }

      expect(past.label_fr).to eq("Services")
      expect(now.label_fr).to eq("Outside services")
    end

    it "keeps the account in the class it was in" do
      post_entry(BigDecimal("10"))
      at = instant
      expense.update!(account_type: :liability, normal_balance: :credit)

      past = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, known_at: at).call.find { |r| r.code == "604000" }

      expect(past.account_type).to eq("expense")
      expect(past.normal_balance).to eq("debit")
    end

    it "shows a partner renamed since with the name it had, in the aged balance" do
      customer = create(:account, :customer, reconcilable: true)
      partner = create(:partner, name: "Alice")
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 3, reference: "M-A")
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: customer, partner: partner, debit: 10, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: expense, debit: 0, credit: 10)
      entry.post!
      next_posting_instant
      at = instant
      partner.update!(name: "Alice Cooper")

      past = Accounting::AgedBalanceQuery.new(kind: :customer, known_at: at).call.sole
      now = Accounting::AgedBalanceQuery.new(kind: :customer).call.sole

      expect(past.partner_name).to eq("Alice")
      expect(now.partner_name).to eq("Alice Cooper")
    end
  end
end

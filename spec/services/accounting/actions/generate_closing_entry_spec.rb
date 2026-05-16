require "rails_helper"

RSpec.describe Accounting::Actions::GenerateClosingEntry do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:misc_journal) { create(:journal, code: "CLO", label_fr: "Clôture", journal_type: :misc, sequence_prefix: "CLO") }
  let!(:result_account) do
    create(:account, code: "699000", label_fr: "Résultat de l'exercice",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let(:purchase_journal) { create(:journal, :purchase) }
  let(:user) { create(:user, role: :accountant) }

  def create_posted_entry(debit_account:, credit_account:, amount:)
    entry = create(:journal_entry, :draft, journal: purchase_journal,
                   fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit_account,
           debit: amount, credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: credit_account,
           debit: BigDecimal("0"), credit: amount)
    entry.post!
    entry
  end

  before do
    create_posted_entry(debit_account: account_604, credit_account: account_440,
                        amount: BigDecimal("1000.00"))
    create_posted_entry(debit_account: account_440, credit_account: account_700,
                        amount: BigDecimal("2000.00"))
  end

  describe ".execute" do
    let(:ctx) do
      LightService::Context.make(
        fiscal_year:     fiscal_year,
        closing_journal: misc_journal,
        result_account:  result_account,
        closed_by:       user
      )
    end

    it "crée une écriture de clôture" do
      expect {
        described_class.execute(ctx)
      }.to change(Accounting::JournalEntry, :count).by(1)
    end

    it "promet closing_entry dans le contexte" do
      described_class.execute(ctx)
      expect(ctx[:closing_entry]).to be_a(Accounting::JournalEntry)
    end

    it "l'écriture de clôture est équilibrée (débit = crédit)" do
      described_class.execute(ctx)
      entry = ctx[:closing_entry]
      debit  = entry.lines.sum(:debit)
      credit = entry.lines.sum(:credit)
      expect((debit - credit).abs).to be <= BigDecimal("0.01")
    end

    it "ne fail pas le contexte" do
      described_class.execute(ctx)
      expect(ctx).to be_success
    end

    context "avec bénéfice net positif (produits > charges)" do
      let!(:revenue_account) do
        create(:account, code: "700100", label_fr: "Ventes produits",
               account_type: :revenue, normal_balance: :credit, account_class: 7)
      end

      before do
        create_posted_entry(debit_account: account_440, credit_account: revenue_account,
                            amount: BigDecimal("5000.00"))
      end

      it "couvre le loop classe 7 : le compte de produit est débité dans l'écriture" do
        described_class.execute(ctx)
        entry = ctx[:closing_entry]
        expect(entry).to be_a(Accounting::JournalEntry)
        revenue_line = entry.lines.find_by(account_id: revenue_account.id)
        expect(revenue_line).to be_present
        expect(revenue_line.debit).to eq(BigDecimal("5000.00"))
      end
    end

    context "sans activité classe 6 ou 7" do
      it "ne crée pas d'écriture si aucun mouvement" do
        fy = create(:fiscal_year, :closed, year: 2099,
                    start_date: Date.new(2099, 1, 1),
                    end_date: Date.new(2099, 12, 31))
        empty_ctx = LightService::Context.make(
          fiscal_year: fy, closing_journal: misc_journal,
          result_account: result_account, closed_by: user
        )
        expect {
          described_class.execute(empty_ctx)
        }.not_to change(Accounting::JournalEntry, :count)
        expect(empty_ctx).to be_success
      end
    end
  end
end

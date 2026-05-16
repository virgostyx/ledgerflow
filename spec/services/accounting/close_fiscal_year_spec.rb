require "rails_helper"

RSpec.describe Accounting::CloseFiscalYear do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:misc_journal)   { create(:journal, code: "CLO", label_fr: "Clôture", journal_type: :misc, sequence_prefix: "CLO") }
  let!(:result_account) do
    create(:account, code: "699000", label_fr: "Résultat de l'exercice",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:user) { create(:user, role: :accountant) }

  def create_posted_entry(amount:)
    entry = create(:journal_entry, :draft, journal: purchase_journal,
                   fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604,
           debit: amount, credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: account_440,
           debit: BigDecimal("0"), credit: amount)
    entry.post!
    entry
  end

  context "succès — exercice propre sans brouillon" do
    before { create_posted_entry(amount: BigDecimal("1000.00")) }

    subject(:result) { described_class.call(fiscal_year: fiscal_year, closed_by: user) }

    it "retourne un contexte de succès" do
      expect(result).to be_success
    end

    it "clôture l'exercice" do
      result
      expect(fiscal_year.reload.status).to eq("closed")
    end

    it "enregistre la date de clôture" do
      result
      expect(fiscal_year.reload.closed_at).to be_present
    end

    it "enregistre l'utilisateur clôturant" do
      result
      expect(fiscal_year.reload.closed_by_id).to eq(user.id)
    end
  end

  context "échec — écritures brouillon existantes" do
    before do
      create(:journal_entry, :draft, journal: purchase_journal,
             fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
    end

    it "retourne un contexte d'échec" do
      result = described_class.call(fiscal_year: fiscal_year, closed_by: user)
      expect(result).to be_failure
    end

    it "ne clôture pas l'exercice" do
      described_class.call(fiscal_year: fiscal_year, closed_by: user)
      expect(fiscal_year.reload.status).to eq("open")
    end
  end

  context "échec — journal de clôture absent" do
    before { misc_journal.update!(active: false) }

    it "retourne un contexte d'échec" do
      result = described_class.call(fiscal_year: fiscal_year, closed_by: user)
      expect(result).to be_failure
    end
  end

  context "erreur inattendue lors de la transaction" do
    before do
      allow(ApplicationRecord).to receive(:transaction).and_raise(RuntimeError, "DB connection lost")
    end

    it "retourne un contexte d'échec" do
      result = described_class.call(fiscal_year: fiscal_year, closed_by: user)
      expect(result).to be_failure
    end

    it "inclut le message d'erreur" do
      result = described_class.call(fiscal_year: fiscal_year, closed_by: user)
      expect(result.message).to include("DB connection lost")
    end
  end

  context "échec — exercice déjà clôturé" do
    before { fiscal_year.update!(status: :closed, closed_at: Time.current, closed_by_id: user.id) }

    it "retourne un contexte d'échec" do
      result = described_class.call(fiscal_year: fiscal_year, closed_by: user)
      expect(result).to be_failure
    end
  end
end

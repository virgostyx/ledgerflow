require "rails_helper"

RSpec.describe Accounting::BankAccount, type: :model do
  include_context "with_pcmn_accounts"

  let(:bank_journal) { create(:journal, :bank, default_account: account_550) }

  describe "associations" do
    it { should belong_to(:journal).class_name("Accounting::Journal") }
    it { should have_many(:transactions).class_name("Accounting::BankTransaction").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:bank_account, journal: bank_journal) }

    it { should validate_presence_of(:label_fr) }
    it { should validate_presence_of(:iban) }
    it { should validate_uniqueness_of(:journal_id) }

    it "rejects an invalid IBAN" do
      expect(build(:bank_account, journal: bank_journal, iban: "BE00000000000000")).not_to be_valid
    end

    it "accepts a valid Belgian IBAN" do
      expect(build(:bank_account, journal: bank_journal, iban: "BE71096123456769")).to be_valid
    end

    it "accepts a non-EUR account with a local account number instead of an IBAN" do
      expect(build(:bank_account, journal: bank_journal, currency: "USD", iban: "0012-345678")).to be_valid
    end

    it "still requires a valid IBAN for an EUR account" do
      expect(build(:bank_account, journal: bank_journal, currency: "EUR", iban: "0012345678")).not_to be_valid
    end

    context "without an IBAN (a bank outside SEPA, in euros)" do
      it "accepts a local account number when the account is flagged no_iban and has a BIC" do
        expect(build(:bank_account, journal: bank_journal, currency: "EUR", iban: "0012345678", bic: "ZANAZMLU", no_iban: true)).to be_valid
      end

      it "requires the BIC/SWIFT" do
        account = build(:bank_account, journal: bank_journal, currency: "EUR", iban: "0012345678", bic: nil, no_iban: true)
        expect(account).not_to be_valid
        expect(account.errors[:bic]).to be_present
      end

      it "refuses a BIC that is neither 8 nor 11 characters" do
        expect(build(:bank_account, journal: bank_journal, currency: "EUR", iban: "0012345678", bic: "ZANA", no_iban: true)).not_to be_valid
      end

      it "still refuses a local number on an unflagged euro account" do
        expect(build(:bank_account, journal: bank_journal, currency: "EUR", iban: "0012345678", bic: "ZANAZMLU")).not_to be_valid
      end

      it "is not flagged by default" do
        expect(build(:bank_account, journal: bank_journal).no_iban).to be(false)
      end
    end

    it "rejects a currency that is not a 3-letter ISO code" do
      expect(build(:bank_account, journal: bank_journal, currency: "dollar")).not_to be_valid
    end

    it "requires journal to be of type bank" do
      misc_journal = create(:journal)
      account = build(:bank_account, journal: misc_journal)
      expect(account).not_to be_valid
      expect(account.errors[:journal]).to be_present
    end
  end

  describe "defaults" do
    subject { build(:bank_account, journal: bank_journal) }

    it { expect(subject.active).to be true }
    it { expect(subject.currency).to eq("EUR") }
  end

  describe "#destroyable?" do
    let(:bank_account) { create(:bank_account, journal: bank_journal) }

    it "returns true when no transactions exist" do
      expect(bank_account.destroyable?).to be true
    end

    it "returns false when transactions exist" do
      create(:bank_transaction, bank_account: bank_account)
      expect(bank_account.destroyable?).to be false
    end
  end

  describe "#balance_from_transactions" do
    let(:bank_account) { create(:bank_account, journal: bank_journal) }

    it "returns 0 when no reconciled transactions" do
      create(:bank_transaction, bank_account: bank_account, status: :pending,
             amount: BigDecimal("500.00"))
      expect(bank_account.balance_from_transactions).to eq(0)
    end

    it "sums only reconciled transactions" do
      create(:bank_transaction, bank_account: bank_account, status: :reconciled,
             amount: BigDecimal("1000.00"))
      create(:bank_transaction, bank_account: bank_account, status: :reconciled,
             amount: BigDecimal("250.00"))
      create(:bank_transaction, bank_account: bank_account, status: :pending,
             amount: BigDecimal("500.00"))
      expect(bank_account.balance_from_transactions).to eq(BigDecimal("1250.00"))
    end
  end
end

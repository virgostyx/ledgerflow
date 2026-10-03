require "rails_helper"

# F02: a payment that differs from the invoice by at most the tolerance (0,05 € by default) is matched all the same, and the
# difference goes to a dedicated rounding account: a charge when the invoice was settled for more than received, an income
# otherwise. Without the two rounding accounts (the owner creates them), the tolerance does nothing.
RSpec.describe "Rounding differences on bank receipts" do
  include_context "with_open_fiscal_year"

  let!(:bank_gl)     { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:receivable)  { create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account) { create(:bank_account, journal: bank_journal) }
  let(:partner) { create(:partner, name: "DUPONT ET FILS SPRL", iban: CodaBuilder.iban("091012345678")) }
  let(:invoice) { create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("1210")) } }
  let(:loss) { Accounting::Account.find_by(code: Accounting::AccountCodes::ROUNDING_LOSS) }
  let(:gain) { Accounting::Account.find_by(code: Accounting::AccountCodes::ROUNDING_GAIN) }

  def structured = Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id))
  def line(amount, **attrs) = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s), description: structured, **attrs)

  describe Accounting::CreateRoundingAccounts do
    let(:owner) { create(:user, role: :admin) }
    let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }

    it "creates the two accounts, a charge and an income, once, and audits it" do
      expect(described_class.call(user: owner)).to be_success
      expect(described_class.call(user: owner)).to be_success # idempotent

      expect(Accounting::Account.where(code: [ "658100", "758100" ]).pluck(:code, :account_type)).to contain_exactly([ "658100", "expense" ], [ "758100", "revenue" ])
      expect(Accounting::AuditLog.where(action: "rounding_accounts_created").count).to eq(1)
    end

    it "is refused to anyone but an owner" do
      accountant = create(:user, role: :accountant)
      create(:user_entity, :accountant, user: accountant, entity: entity)

      expect(described_class.call(user: accountant)).to be_failure
      expect(Accounting::Account.where(code: "658100")).to be_empty
    end

    it "is part of the chart of a new entity" do
      %w[pcmn_commercial pcmn_asbl].each do |file|
        codes = JSON.parse(File.read(Rails.root.join("db/seeds/#{file}.json"))).map { |a| a["code"] }
        expect(codes).to include("658100", "758100")
      end
    end
  end

  context "with the rounding accounts" do
    before do
      create(:account, code: "658100", label_fr: "Rounding (charge)", account_class: 6, account_type: :expense, normal_balance: :debit)
      create(:account, code: "758100", label_fr: "Rounding (income)", account_class: 7, account_type: :revenue, normal_balance: :credit)
    end

    it "matches a payment a few cents short at 100, saying the difference" do
      expect(Accounting::MatchBankTransaction.call(transaction: line(1209.97))).to have_attributes(kind: :invoice, score: 100, rule: 1, confidence: :high, rounding: BigDecimal("0.03"))
    end

    it "matches a payment a few cents over, the difference being negative" do
      expect(Accounting::MatchBankTransaction.call(transaction: line(1210.04))).to have_attributes(score: 100, rounding: BigDecimal("-0.04"))
    end

    it "keeps 80 for a difference above the tolerance, and 100 without any difference" do
      expect(Accounting::MatchBankTransaction.call(transaction: line(1209.90))).to have_attributes(score: 80, rounding: BigDecimal("0"))
      expect(Accounting::MatchBankTransaction.call(transaction: line(1210))).to have_attributes(score: 100, rounding: BigDecimal("0"))
    end

    it "follows the tolerance of the entity, 0 meaning exact amounts only" do
      entity.update!(bank_rounding_tolerance: 0)

      expect(Accounting::MatchBankTransaction.call(transaction: line(1209.97))).to have_attributes(score: 80)
    end

    it "applies to rules 2 and 3 as well (invoice number, IBAN)" do
      invoice.update_columns(invoice_number: "VT2026/0099")

      expect(Accounting::MatchBankTransaction.call(transaction: line(1209.98, description: "PAIEMENT VT2026/0099"))).to have_attributes(rule: 2, rounding: BigDecimal("0.02"))
      expect(Accounting::MatchBankTransaction.call(transaction: line(1209.98, description: "VIREMENT", counterparty_iban: partner.iban))).to have_attributes(rule: 3, rounding: BigDecimal("0.02"))
    end

    it "books a payment a few cents short as a draft: bank, the whole invoice settled, the difference as a charge" do
      tx = line(1209.97)

      Banking::AutoMatch.call(transactions: [ tx ])

      entry = tx.reload.journal_entry
      expect(tx).to be_matched
      expect(entry).to be_draft
      expect(entry.lines.find_by(account: bank_gl).debit).to eq(BigDecimal("1209.97"))
      expect(entry.lines.find_by(account: receivable)).to have_attributes(credit: BigDecimal("1210"), invoice_id: invoice.id)
      expect(entry.lines.find_by(account: loss).debit).to eq(BigDecimal("0.03"))
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it "books a payment a few cents over with the difference as an income" do
      tx = line(1210.03)

      Banking::AutoMatch.call(transactions: [ tx ])

      entry = tx.reload.journal_entry
      expect(entry.lines.find_by(account: receivable).credit).to eq(BigDecimal("1210"))
      expect(entry.lines.find_by(account: gain).credit).to eq(BigDecimal("0.03"))
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it "pays the invoice, settles the line and leaves nothing owed once the entry is validated" do
      tx = line(1209.97)
      Banking::AutoMatch.call(transactions: [ tx ])

      expect(Accounting::PostJournalEntry.call(entry: tx.reload.journal_entry)).to be_success

      expect(tx.reload).to be_reconciled
      expect(invoice.reload).to be_paid
      expect(invoice.remaining_amount).to eq(0)
    end

    it "does the same when a person confirms the suggestion" do
      tx = line(1209.97)

      expect(Accounting::AcceptBankSuggestion.call(transaction: tx)).to be_success

      expect(tx.reload).to be_reconciled
      expect(invoice.reload).to be_paid
    end
  end

  context "without the rounding accounts" do
    it "does not use the tolerance: the payment stays a partial suggestion" do
      expect(Accounting::MatchBankTransaction.call(transaction: line(1209.97))).to have_attributes(score: 80, rounding: BigDecimal("0"))
    end
  end
end

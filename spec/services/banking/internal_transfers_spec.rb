require "rails_helper"

# F02: a transfer between two bank accounts of the entity shows as two lines, one on each statement. They are paired and each is
# booked against the transit account 580000 (virements internes), so that the two cancel out, with no difference.
RSpec.describe Banking::InternalTransfers do
  include_context "with_open_fiscal_year"

  let!(:gl_a)     { create(:account, code: "550000", label_fr: "Banque A", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:gl_b)     { create(:account, code: "550100", label_fr: "Banque B", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:transit)  { create(:account, code: "580000", label_fr: "Virements internes", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:journal_a) { create(:journal, :bank, code: "BNQ1", default_account: gl_a) }
  let!(:journal_b) { create(:journal, :bank, code: "BNQ2", default_account: gl_b) }
  let(:account_a) { create(:bank_account, journal: journal_a) }
  let(:account_b) { create(:bank_account, journal: journal_b) }
  let(:user) { create(:user) }

  def out_of_a(amount = 500, **attrs) = create(:bank_transaction, bank_account: account_a, amount: -amount, counterparty_iban: account_b.iban, description: "VIREMENT", **attrs)
  def into_b(amount = 500, **attrs) = create(:bank_transaction, bank_account: account_b, amount: amount, counterparty_iban: account_a.iban, description: "VIREMENT", **attrs)
  def run(*lines) = Banking::AutoMatch.call(transactions: lines)

  describe "a pair" do
    let!(:debit)  { out_of_a(transaction_date: Date.current) }
    let!(:credit) { into_b(transaction_date: Date.current + 1) }

    it "is booked as two drafts against the transit account, each in its bank's journal, and both lines become matched" do
      result = run(debit, credit)

      expect([ debit.reload, credit.reload ]).to all(be_matched)
      expect(debit.journal_entry.journal).to eq(journal_a)
      expect(credit.journal_entry.journal).to eq(journal_b)
      expect(debit.journal_entry.lines.find_by(account: transit).debit).to eq(500)
      expect(credit.journal_entry.lines.find_by(account: transit).credit).to eq(500)
      expect(debit.match_data).to include("kind" => "transfer", "pair_id" => credit.id, "auto" => true)
      expect(credit.match_data).to include("kind" => "transfer", "pair_id" => debit.id)
      expect(result[:transfers]).to eq(1)
    end

    it "audits the pairing" do
      run(debit, credit)

      expect(Accounting::AuditLog.where(action: "bank_transfer_matched", auditable_id: debit.id).sole.payload).to include("pair_id" => credit.id)
    end

    it "is found from either line, and booked once" do
      run(credit)
      run(debit)

      expect(Accounting::JournalEntry.draft.count).to eq(2)
    end

    it "settles both lines when both drafts are validated, and letters the two transit lines" do
      run(debit, credit)

      Accounting::PostJournalEntry.call(entry: debit.reload.journal_entry)
      expect(debit.reload).to be_reconciled
      expect(credit.reload).to be_matched
      expect(Accounting::JournalEntryLine.where(account: transit).where.not(lettering_id: nil)).to be_empty

      Accounting::PostJournalEntry.call(entry: credit.journal_entry)
      expect(credit.reload).to be_reconciled
      lines = Accounting::JournalEntryLine.where(account: transit)
      expect(lines.count).to eq(2)
      expect(lines.map(&:lettering_id).uniq.size).to eq(1)
      expect(lines.sum(:debit)).to eq(lines.sum(:credit))
    end

    it "is undone on both lines at once, drafts or validated" do
      run(debit, credit)

      expect(Banking::UndoMatch.call(transaction: debit.reload, user: user)).to be_success

      expect([ debit.reload, credit.reload ]).to all(be_pending)
      expect(Accounting::JournalEntry.draft.count).to eq(0)
    end

    it "is undone once validated and lettered: unlettered, both entries reversed, both lines pending" do
      run(debit, credit)
      [ debit, credit ].each { |tx| Accounting::PostJournalEntry.call(entry: tx.reload.journal_entry) }

      result = Banking::UndoMatch.call(transaction: debit.reload, user: user, reason: "Wrong account")

      expect(result).to be_success
      expect([ debit.reload, credit.reload ]).to all(be_pending)
      expect(Accounting::JournalEntry.where(status: :reversed).count).to eq(2)
    end
  end

  describe "what is not a pair" do
    it "needs equal amounts, opposite signs, two accounts, within three days, and one of the lines naming the other account" do
      a = out_of_a
      expect(run(a, into_b(499))[:transfers]).to eq(0)                                   # another amount
      expect(run(a, into_b(500, transaction_date: Date.current + 4))[:transfers]).to eq(0) # too far apart
      same = create(:bank_transaction, bank_account: account_a, amount: 500, counterparty_iban: account_a.iban)
      expect(run(a, same)[:transfers]).to eq(0)                                           # the same account
      stranger = create(:bank_transaction, bank_account: account_b, amount: 500, counterparty_iban: CodaBuilder.iban("091012345678"))
      a.update!(counterparty_iban: CodaBuilder.iban("091012345678"))
      expect(run(a, stranger)[:transfers]).to eq(0)                                       # neither names the other account
      expect([ a.reload, stranger.reload ]).to all(be_pending)
    end

    it "is left to a person when two lines could be the other half" do
      debit = out_of_a
      into_b
      into_b

      expect(run(debit)[:transfers]).to eq(0)
      expect(debit.reload).to be_pending
    end

    it "is left alone without the transit account, or in a foreign currency" do
      debit = out_of_a
      credit = into_b
      transit.destroy

      expect(run(debit, credit)[:transfers]).to eq(0)
    end
  end
end

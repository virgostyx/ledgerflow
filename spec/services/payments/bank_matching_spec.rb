require "rails_helper"

# B01c: rule 0 joins the bank matching of F02. What it finds is only ever proposed: the automatic matching keeps it for a person and books nothing; the person who accepts
# confirms the debit (draft entries), with the right to confirm.
RSpec.describe "Bank matching of payment batches (rule 0)" do
  include_context "with submitted batch"

  let(:batch) { submitted_batch(posted) }
  let(:line) { debit_line(1210, description: "Remise #{batch.reference}") }

  before { batch }

  it "is the first rule: a debit that names a batch is a suggestion of the kind payment batch debit, with the score and the rule of the recognition" do
    suggestion = Accounting::MatchBankTransaction.call(transaction: line)

    expect(suggestion).to have_attributes(kind: :payment_batch_debit, target: batch, score: 100, rule: "0A", confidence: :high)
    expect(suggestion.proposal.items).to eq(batch.items.to_a)
  end

  it "gives way to nothing before it, and leaves the rest of the matching to the rules that were there" do
    plain = debit_line(33, description: "Something else")

    expect(Accounting::MatchBankTransaction.call(transaction: plain)&.kind).not_to eq(:payment_batch_debit)
  end

  it "is not looked for when the company does not use the supplier payments" do
    entity.update!(features: entity.features.merge("b01b" => false))

    expect(Accounting::MatchBankTransaction.call(transaction: line.reload)&.kind).not_to eq(:payment_batch_debit)
  end

  describe "the automatic matching" do
    it "keeps the proposal for a person, books nothing, and never validates anything" do
      result = nil
      expect { result = Banking::AutoMatch.call(transactions: [ line ]) }.not_to change(Accounting::JournalEntry, :count)

      expect(result[:suggested]).to eq(1)
      expect(line.reload).to be_pending
      expect(line.match_data).to include("kind" => "payment_batch_debit", "score" => 100, "rule" => "0A", "target_id" => batch.id)
      expect(batch.reload).to be_submitted
    end

    it "keeps a proposal of 70 too (a batch debited but for some payments), since a person has to confirm it" do
      three = submitted_batch(posted(unit_price: 1000), posted(partner: create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago) }, unit_price: 500))
      missing = three.items.find_by(holder_name: "Beta Corp")
      partial = debit_line(three.total - missing.amount, description: three.reference)

      Banking::AutoMatch.call(transactions: [ partial ])

      expect(partial.reload.match_data).to include("score" => 70, "rule" => "0C")
    end
  end

  describe "accepting the suggestion" do
    it "confirms the debit as the person who accepts: one draft entry per payment, the line matched" do
      Current.set(user: exporter) { Accounting::AcceptBankSuggestion.call(transaction: line) }

      expect(batch.reload).to be_debited
      expect(batch.items.first.journal_entry).to be_draft
      expect(line.reload).to be_matched
    end

    it "refuses a person who may not confirm" do
      assistant = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }

      result = Current.set(user: assistant) { Accounting::AcceptBankSuggestion.call(transaction: line) }

      expect(result).to be_failure
      expect(batch.reload).to be_submitted
    end
  end
end

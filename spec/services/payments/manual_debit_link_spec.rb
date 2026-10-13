require "rails_helper"

# B01c §6 "Confirmation manuelle": a debit confirmed by hand, with no line of the statement, is flagged in R19 until the statement that holds it is reconciled. When the line
# comes, it is recognised for that batch and linked to its payments (no entry is made twice).
RSpec.describe "A debit confirmed by hand, then found on the statement" do
  include_context "with submitted batch"

  let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:batch) { submitted_batch(posted) }
  let(:check) { Accounting::Consistency::Checks::C22ManualDebitWithoutStatement }

  before do
    Payments::ConfirmDebit.manual(batch: batch, user: exporter, reason: "The bank confirmed by phone", date: execution, bank_reference: "BANK-REF-1").tap { |r| raise r.message if r.failure? }
    batch.reload
  end

  it "is flagged by R19 as long as no statement holds it" do
    findings = check.new.call

    expect(findings.map(&:subject_id)).to eq([ batch.id ])
    expect(findings.first).to have_attributes(severity: "warning", check_id: "C22")
    expect(findings.first.message).to include(batch.reference).and include("BANK-REF-1")
  end

  it "is recognised when the line comes, with the right to link it, and no second entry is made" do
    line = debit_line(batch.total, description: "Remise #{batch.reference}")

    proposal = Payments::RecognizeDebit.call(line)

    expect(proposal).to have_attributes(batch: batch, score: 100, link: true)
    expect { Current.set(user: exporter) { Accounting::AcceptBankSuggestion.call(transaction: line) } }.not_to change(Accounting::JournalEntry, :count)
    expect(batch.items.reload.map(&:bank_transaction_id)).to eq([ line.id ])
    expect(line.reload).to be_matched
  end

  it "settles the line once the entries are validated, and the flag is gone" do
    line = debit_line(batch.total, description: "Remise #{batch.reference}")
    Current.set(user: exporter) { Accounting::AcceptBankSuggestion.call(transaction: line) }

    Payments::PostBatchPayments.call(batch: batch.reload, user: poster).tap { |r| raise r.message if r.failure? }

    expect(line.reload).to be_reconciled
    expect(check.new.call).to be_empty
  end

  it "is not proposed twice: the linked batch is no longer waiting for a line" do
    first = debit_line(batch.total, description: batch.reference)
    Current.set(user: exporter) { Accounting::AcceptBankSuggestion.call(transaction: first) }

    expect(Payments::RecognizeDebit.call(debit_line(batch.total, description: batch.reference))).to be_nil
  end

  it "wants the right to confirm" do
    line = debit_line(batch.total, description: batch.reference)
    assistant = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }

    result = Payments::LinkManualDebit.call(batch: batch, user: assistant, transaction: line, items: batch.items.to_a)

    expect(result).to be_failure
    expect(batch.items.reload.map(&:bank_transaction_id)).to eq([ nil ])
  end
end

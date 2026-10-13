require "rails_helper"

# B01c on the bank reconciliation screen: a debit that is the debit of a payment batch is proposed with what it would confirm; the person accepts (or not); a credit that gives a
# payment back is proposed as a return, with a reason to give and a reversal that follows.
RSpec.describe "Bank reconciliation of payment batches (B01c)", type: :request do
  include_context "with submitted batch"

  let(:assistant) { create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:batch) { submitted_batch(posted) }
  let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  before do
    owner
    sign_in exporter
  end

  def accept(line) = patch(accounting_bank_reconciliation_path, params: { bank_reconciliation: { bank_transaction_id: line.id, accept_suggestion: 1 } })

  describe "a debit that is the debit of a batch" do
    let!(:line) { debit_line(1210, description: "Remise #{batch.reference}") }

    it "is suggested with the batch, the number of payments and the total, and a button to accept" do
      get accounting_bank_reconciliation_path

      expect(response.body).to include(batch.reference).and include("1 payment").and include("score 100").and include("Accept")
    end

    it "is confirmed on accept: one draft entry per payment, the batch debited, the line matched" do
      accept(line)

      expect(response).to redirect_to(accounting_bank_reconciliation_path)
      expect(flash[:alert]).to be_nil
      expect(batch.reload).to be_debited
      expect(batch.items.first.journal_entry).to be_draft
      expect(line.reload).to be_matched
    end

    it "is refused to a person who may not confirm, and nothing is made" do
      sign_in assistant

      accept(line)

      expect(batch.reload).to be_submitted
      expect(line.reload).to be_pending
    end

    it "warns when the cancellation of the batch was asked for" do
      Payments::CancelBatch.call(batch: batch, user: exporter, reason: "changed my mind")

      get accounting_bank_reconciliation_path

      expect(response.body).to match(/cancellation.*asked/i)
    end
  end

  describe "a credit that gives a payment back" do
    before do
      Payments::ConfirmDebit.call(batch: batch, user: exporter, transaction: debit_line(1210, description: batch.reference), items: batch.items.to_a).tap { |r| raise r.message if r.failure? }
      Payments::PostBatchPayments.call(batch: batch.reload, user: poster).tap { |r| raise r.message if r.failure? }
    end

    let!(:credit) { create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution + 3, counterparty_iban: "BE68539007547034", description: "Return") }

    it "is suggested as a return, with a reason to give" do
      get accounting_bank_reconciliation_path

      expect(response.body).to include("returned payment").and include(batch.items.first.end_to_end_id).and include("Reverse the payment")
    end

    it "is registered with a reason: the payment is reversed, the invoice reopened and held" do
      patch accounting_bank_reconciliation_path, params: { bank_reconciliation: { bank_transaction_id: credit.id, register_return: 1, reason: "Wrong account" } }

      expect(flash[:alert]).to be_nil
      expect(batch.items.first.reload).to be_returned
      expect(credit.reload).to be_reconciled
    end

    it "wants the reason" do
      patch accounting_bank_reconciliation_path, params: { bank_reconciliation: { bank_transaction_id: credit.id, register_return: 1, reason: " " } }

      expect(flash[:alert]).to be_present
      expect(batch.items.first.reload).to be_confirmed
    end

    it "is never booked by itself: accepting the suggestion as such is refused" do
      accept(credit)

      expect(flash[:alert]).to match(/reason/i)
      expect(credit.reload).to be_pending
    end
  end
end

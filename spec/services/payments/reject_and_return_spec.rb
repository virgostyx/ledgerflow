require "rails_helper"

# B01c §6 "Rejets et retours": a payment missing from a partly debited batch is rejected; a credit line that gives back a payment is a return, proposed as a reversal. Both put the
# invoice on hold (so that nothing pays the same IBAN again by itself), send the account back to unverified, and ask a person to contact the supplier.
RSpec.describe "Rejected and returned payments" do
  include_context "with submitted batch"

  def supplier_named(name, iban)
    create(:partner, :supplier, name: name, iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: iban, holder_name: name, created_by: owner, first_seen_at: 90.days.ago) }
  end

  let(:beta) { supplier_named("Beta Corp", "BE71096123456769") }
  let(:acme_invoice) { posted(unit_price: 1000) }
  let(:beta_invoice) { posted(partner: beta, unit_price: 500) }
  let(:batch) { submitted_batch(acme_invoice, beta_invoice) } # 1 210.00 + 605.00
  let(:acme_item) { batch.items.find_by(holder_name: "Acme Ltd") }
  let(:beta_item) { batch.items.find_by(holder_name: "Beta Corp") }
  let(:beta_account) { Accounting::PartnerBankAccount.find_by!(partner: beta) }
  let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  def confirm_acme_only
    Payments::ConfirmDebit.call(batch: batch, user: exporter, transaction: debit_line(1210, description: batch.reference), items: [ acme_item ]).tap { |r| raise r.message if r.failure? }
  end

  def reject(items = [ beta_item ], reason: "Rejected by the bank: account closed", user: exporter) = Payments::RejectPayments.call(batch: batch, items: items, user: user, reason: reason)

  def audit(action, record = batch) = Accounting::AuditLog.for_record(record).for_action(action)

  describe "a payment missing from the debit" do
    before { confirm_acme_only }

    it "is rejected: the batch is closed as partly rejected, the invoice is held with the reason, nothing else pays it" do
      result = reject

      expect(result).to be_success
      expect(beta_item.reload).to be_rejected
      expect(batch.reload).to have_attributes(status: "partially_rejected")
      expect(beta_invoice.reload.payment_status).to eq("on_hold")
      expect(Payments::Hold.active.where(invoice: beta_invoice).pluck(:reason).join).to include("account closed")
      row = Payments::Eligibility.call(execution_date: execution).find { |r| r.invoice.id == beta_invoice.id }
      expect(row.reasons.map(&:code)).to include(:hold)
      expect(Payments::ItemInvoice.where(item_id: beta_item.id).pluck(:active)).to all(be(false))
      expect(audit("payment_rejected").sole.payload).to include("item_id" => beta_item.id, "reason" => "Rejected by the bank: account closed")
    end

    it "sends the account back to unverified for a new observation, warns the owners and asks to contact the supplier" do
      reject

      account = beta_account.reload
      expect(account).to be_unverified
      expect(account.verified_by).to be_nil
      expect(account.cooling_until).to be > Time.current
      expect(Accounting::Task.where(target: beta_invoice).pluck(:title).join).to match(/contact.*Beta Corp/i)
      expect(Accounting::Notification.where(user: owner).count).to be >= 1
      expect(audit("bank_account_distrusted", account).sole.payload).to include("reason" => "payment rejected")
    end

    it "lets the entries of the payments that were debited be validated" do
      reject

      expect(Payments::PostBatchPayments.call(batch: batch.reload, user: poster)).to be_success
      expect(acme_invoice.reload.status).to eq("paid")
    end

    it "wants a reason, the right to confirm, and payments of the batch that still wait" do
      expect(reject(reason: " ")[:code]).to eq(:reason_required)
      expect(reject(user: create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) })[:code]).to eq(:not_allowed)
      expect(reject([ acme_item.reload ])[:code]).to eq(:foreign_items) # confirmed already
      expect(beta_item.reload).to be_included
    end
  end

  describe "a payment that came back" do
    let(:credit_line) { |example| create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution + 3, counterparty_iban: "BE68539007547034", description: "Return of payment") }

    before do
      Payments::ConfirmDebit.call(batch: batch, user: exporter, transaction: debit_line(batch.total, description: batch.reference), items: batch.items.to_a).tap { |r| raise r.message if r.failure? }
      Payments::PostBatchPayments.call(batch: batch.reload, user: poster).tap { |r| raise r.message if r.failure? }
    end

    describe "recognising it" do
      it "is a credit of the same amount from the account paid, within 30 days of the debit" do
        proposal = Payments::RecognizeReturn.call(credit_line)

        expect(proposal).to have_attributes(item: acme_item)
      end

      it "is nothing after 30 days, from another account, for another amount, for a payment not confirmed, or when two payments could be it" do
        expect(Payments::RecognizeReturn.call(create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution + 31, counterparty_iban: "BE68539007547034"))).to be_nil
        expect(Payments::RecognizeReturn.call(create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution + 3, counterparty_iban: "NL91ABNA0417164300"))).to be_nil
        expect(Payments::RecognizeReturn.call(create(:bank_transaction, bank_account: bank, amount: 1209, transaction_date: execution + 3, counterparty_iban: "BE68539007547034"))).to be_nil
        expect(Payments::RecognizeReturn.call(create(:bank_transaction, bank_account: bank, amount: -1210, transaction_date: execution + 3, counterparty_iban: "BE68539007547034"))).to be_nil
      end
    end

    describe "registering it" do
      def register(line = credit_line, user: exporter) = Payments::RegisterReturn.call(item: acme_item, transaction: line, user: user, reason: "Returned: wrong account")

      it "reverses the entry of the payment, reopens the invoice and holds it, and the line of the statement is settled against the reversal" do
        result = register

        expect(result).to be_success
        expect(acme_item.reload).to be_returned
        reversal = result[:reversal]
        expect(reversal).to be_posted
        expect(reversal.reversal_of_id).to eq(acme_item.journal_entry_id)
        expect(acme_invoice.reload.status).to eq("posted")
        expect(Payments::OpenAmounts.rests([ acme_invoice ])[acme_invoice.id]).to eq(1210)
        expect(acme_invoice.payment_status).to eq("on_hold")
        expect(Payments::Hold.active.where(invoice: acme_invoice).pluck(:reason).join).to include("returned")
        expect(credit_line.reload.status).to eq("reconciled")
        expect(credit_line.journal_entry_id).to eq(reversal.id)
      end

      it "sends the account back to unverified, warns the owners, asks to contact the supplier, and says so in the audit trail" do
        register

        account = Accounting::PartnerBankAccount.find_by!(partner: supplier, status: :unverified)
        expect(account.cooling_until).to be > Time.current
        expect(Accounting::Task.where(target: acme_invoice).pluck(:title).join).to match(/contact.*Acme/i)
        expect(audit("payment_returned", acme_item.batch).sole.payload).to include("item_id" => acme_item.id, "transaction_id" => credit_line.id)
      end

      it "is made once, and by a person who may confirm" do
        register

        expect(register(create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution + 4, counterparty_iban: "BE68539007547034"))).to be_failure
        expect(Payments::RegisterReturn.call(item: beta_item, transaction: create(:bank_transaction, bank_account: bank, amount: 605, transaction_date: execution + 4, counterparty_iban: "BE71096123456769"), user: create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }, reason: "x")).to be_failure
      end

      it "wants the amount of the payment" do
        expect(register(create(:bank_transaction, bank_account: bank, amount: 1000, transaction_date: execution + 3, counterparty_iban: "BE68539007547034"))[:code]).to eq(:amount_mismatch)
      end
    end
  end
end

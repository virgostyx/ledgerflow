require "rails_helper"

# B01c §6 "Confirmation du paiement": a person confirms that the bank debited a batch (from the line of the statement, or by hand when the statement has none). One DRAFT entry per
# payment - debit the suppliers' account on the invoices paid, credit the bank - never two for the same payment, nothing validated and nothing lettered yet.
RSpec.describe Payments::ConfirmDebit do
  include_context "with submitted batch"

  let(:beta) do
    create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago) }
  end
  let(:acme_invoice) { posted(unit_price: 1000) }
  let(:beta_invoice) { posted(partner: beta, unit_price: 500) }
  let(:batch) { submitted_batch(acme_invoice, beta_invoice) } # 1 210.00 + 605.00 = 1 815.00
  let(:acme_item) { batch.items.find_by(holder_name: "Acme Ltd") }
  let(:beta_item) { batch.items.find_by(holder_name: "Beta Corp") }

  def confirm(items = batch.items.to_a, line: debit_line(batch.total, description: batch.reference), user: exporter, target: batch)
    described_class.call(batch: target, user: user, transaction: line, items: items)
  end

  def audit(action) = Accounting::AuditLog.for_record(batch).for_action(action)

  let(:suppliers) { Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS) }

  describe "from the line of the statement" do
    it "makes one draft entry per payment: debit the suppliers' account on the invoice paid, credit the bank, dated as the line, referenced as the payment" do
      line = debit_line(batch.total, description: batch.reference, on: execution + 1)
      result = confirm(line: line)

      expect(result).to be_success
      entry = acme_item.reload.journal_entry
      expect(entry).to be_draft
      expect(entry).to have_attributes(reference: acme_item.end_to_end_id, entry_date: execution + 1, source_type: "Payments::Item", source_id: acme_item.id, journal: bank.journal)
      expect(entry.description).to include(batch.reference).and include("Acme Ltd")
      debit, credit = entry.lines.order(:id).to_a
      expect(debit).to have_attributes(account: suppliers, partner: supplier, invoice_id: acme_invoice.id, debit: 1210, credit: 0)
      expect(credit).to have_attributes(account: bank.journal.default_account, debit: 0, credit: 1210)
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it "ties each payment to the line, says who confirmed and when, and leaves the batch debited with the line matched to its entries" do
      line = debit_line(batch.total, description: batch.reference)
      confirm(line: line)

      expect(batch.items.reload).to all(have_attributes(status: "confirmed", bank_transaction_id: line.id, confirmed_by: exporter, confirmed_at: Time.current))
      expect(batch.reload).to have_attributes(status: "debited", debit_kind: "statement", debited_by: exporter, debited_at: Time.current)
      expect(line.reload).to be_matched
      expect(line.match_data).to include("kind" => "payment_batch", "batch_id" => batch.id)
      expect(audit("payment_batch_debit_confirmed").sole.payload).to include("entries" => 2, "total" => "1815.00", "transaction_id" => line.id)
    end

    it "keeps the invoices held until their entries are validated, so that no other batch can take them" do
      confirm

      expect(Payments::ItemInvoice.where(item_id: batch.items.select(:id)).pluck(:active)).to all(be(true))
      expect(Payments::Eligibility.call(execution_date: execution).find { |row| row.invoice.id == acme_invoice.id }.reasons.map(&:code)).to include(:in_batch)
    end

    it "pays nothing yet: the invoices stay open and the entries are drafts, nothing is lettered" do
      confirm

      expect(batch.items.map { |i| i.reload.journal_entry }).to all(be_draft)
      expect(Payments::OpenAmounts.rests([ acme_invoice.reload, beta_invoice.reload ]).values).to eq([ 1210, 605 ])
    end

    it "does it once: the same confirmation again makes no second entry" do
      line = debit_line(batch.total, description: batch.reference)
      confirm(line: line)

      expect { confirm(line: line) }.not_to change(Accounting::JournalEntry, :count)
      expect(confirm(line: line)).to be_failure
    end

    it "takes only some payments when the line is the line of one payment, and the batch is debited when all were" do
      line_a = debit_line(1210, counterparty_iban: "BE68539007547034")
      confirm([ acme_item ], line: line_a)
      expect(batch.reload).not_to be_debited
      expect(acme_item.reload).to be_confirmed
      expect(beta_item.reload).to be_included

      confirm([ beta_item ], line: debit_line(605, counterparty_iban: "BE71096123456769"))
      expect(batch.reload).to be_debited
    end

    it "nets a credit note: debit the invoice, credit the credit note, credit the bank for the difference" do
      invoice = posted(unit_price: 1000)
      credit_note = posted(unit_price: 100, document_type: :credit_note)
      credit_note # posted, not selected: a credit note is netted, never picked
      netted = submitted_batch(invoice, net: true)
      item = netted.items.sole
      expect(item.amount).to eq(1089)

      confirm([ item ], line: debit_line(1089), target: netted)

      lines = item.reload.journal_entry.lines.order(:id).map { |l| [ l.account.code, l.invoice_id, l.debit, l.credit ] }
      expect(lines).to contain_exactly([ "440000", invoice.id, 1210, 0 ], [ "440000", credit_note.id, 0, 121 ], [ bank.journal.default_account.code, nil, 0, 1089 ])
    end
  end

  describe "what it refuses" do
    it "a line that is not a debit of this account for this batch, or a total that is not the payments'" do
      expect(confirm(line: debit_line(batch.total - 1))[:code]).to eq(:amount_mismatch)
      expect(confirm(line: debit_line(batch.total, bank_account: create(:bank_account)))[:code]).to eq(:wrong_account)
      expect(confirm(line: create(:bank_transaction, bank_account: bank, amount: batch.total, transaction_date: execution))[:code]).to eq(:not_a_debit)
      expect(confirm(line: debit_line(batch.total, status: :reconciled))[:code]).to eq(:line_not_pending)
      expect(batch.items.reload.map(&:status).uniq).to eq([ "included" ])
    end

    it "a batch that is not waiting for its debit: given up, still a draft, already debited" do
      line = debit_line(batch.total)
      Payments::CancelBatch.call(batch: batch, user: exporter, reason: "x")
      Payments::ConfirmCancellation.call(batch: batch.reload, user: exporter)
      expect(confirm(line: line)[:code]).to eq(:not_waiting)
      expect(confirm(line: line, target: batch_of(posted(unit_price: 40)))[:code]).to eq(:not_waiting)
    end

    it "a person without the right to confirm, and a company without the feature" do
      expect(confirm(user: preparer.tap { |u| u.user_entities.update_all(role: UserEntity.roles[:assistant]) })[:code]).to eq(:not_allowed)
      entity.update!(features: entity.features.merge("b01b" => false))
      expect(confirm(target: batch.reload)[:code]).to eq(:feature_off)
    end

    it "a payment that is not of the batch" do
      other = submitted_batch(posted(unit_price: 40))

      expect(confirm(other.items.to_a, line: debit_line(other.total))[:code]).to eq(:foreign_items)
    end

    it "a date with no open fiscal year to book in" do
      line = debit_line(batch.total, on: execution + 400)

      expect(confirm(line: line)[:code]).to eq(:no_fiscal_year)
    end
  end

  describe "by hand, when the statement has no line" do
    def confirm_by_hand(reason: "The bank confirmed by phone", date: execution, reference: "BANK-REF-77", user: exporter, target: batch)
      described_class.manual(batch: target, user: user, reason: reason, date: date, bank_reference: reference)
    end

    it "makes the same entries, dated as said, and keeps the reason, the date and the reference of the bank on the batch" do
      result = confirm_by_hand

      expect(result).to be_success
      expect(batch.reload).to have_attributes(status: "debited", debit_kind: "manual", debit_reason: "The bank confirmed by phone", debit_reference: "BANK-REF-77", debit_date: execution)
      expect(batch.items.map { |i| i.journal_entry.entry_date }.uniq).to eq([ execution ])
      expect(batch.items.map(&:bank_transaction_id).uniq).to eq([ nil ])
      expect(audit("payment_batch_debit_confirmed_by_hand").sole.payload).to include("reason" => "The bank confirmed by phone", "bank_reference" => "BANK-REF-77")
    end

    it "wants a reason, a date and a reference, and a batch that was said to be loaded in the bank" do
      expect(confirm_by_hand(reason: " ")[:code]).to eq(:reason_required)
      expect(confirm_by_hand(date: nil)[:code]).to eq(:date_required)
      expect(confirm_by_hand(reference: "")[:code]).to eq(:reference_required)
      expect(confirm_by_hand(target: batch_of(posted(unit_price: 40)))[:code]).to eq(:not_waiting)
      Payments::Batch.where(id: batch.id).update_all(status: Payments::Batch.statuses[:exported]) # the file was made, nobody said it was loaded
      expect(confirm_by_hand(target: batch.reload)[:code]).to eq(:not_submitted)
    end

    it "is made once" do
      confirm_by_hand

      expect { confirm_by_hand }.not_to change(Accounting::JournalEntry, :count)
    end
  end
end

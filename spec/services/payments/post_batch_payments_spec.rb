require "rails_helper"

# B01c §6 "Confirmation du paiement", steps 4 to 6: the drafts of a debited batch are validated together by a person (`entries.post`, another one than the preparer with four eyes);
# each payment is then lettered with the invoice it pays - the one exception to manual validation: an exact lettering, deterministic and reversible. A part payment letters partly.
# A payment of an invoice already settled is a probable double payment: nothing is lettered, the invoice is disputed and a task is made.
RSpec.describe Payments::PostBatchPayments do
  include_context "with submitted batch"

  let(:beta) do
    create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago) }
  end
  let(:acme_invoice) { posted(unit_price: 1000) }
  let(:beta_invoice) { posted(partner: beta, unit_price: 500) }
  let(:poster) { create(:user, full_name: "Paula Poster").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:batch) { submitted_batch(acme_invoice, beta_invoice) }
  let(:suppliers) { Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS) }

  def debit!(target = batch)
    Payments::ConfirmDebit.call(batch: target, user: exporter, transaction: debit_line(target.total, description: target.reference), items: target.items.to_a).tap { |r| raise r.message if r.failure? }
    target.reload
  end

  def post_all(target = batch, user: poster) = described_class.call(batch: target, user: user)

  def audit(action) = Accounting::AuditLog.for_record(batch).for_action(action)

  def trade_line(invoice) = invoice.reload.journal_entry.lines.find_by!(account: suppliers)

  describe "an exact payment" do
    before { debit!(batch) }

    it "validates each draft, letters each payment with its invoice, and the invoices are paid" do
      result = post_all

      expect(result).to be_success
      expect(batch.items.map { |i| i.reload.journal_entry }).to all(be_posted)
      expect([ acme_invoice, beta_invoice ].map { |i| i.reload.status }).to all(eq("paid"))
      expect(trade_line(acme_invoice).lettering_id).not_to be_nil
      expect(Payments::OpenAmounts.rests([ acme_invoice, beta_invoice ]).values).to eq([ 0, 0 ])
      expect(audit("payment_batch_entries_posted").sole.payload).to include("entries" => 2, "lettered" => 2)
    end

    it "settles the line of the statement, frees the invoices and says so on them" do
      line = Accounting::BankTransaction.find(batch.items.first.bank_transaction_id)
      post_all

      expect(line.reload).to be_reconciled
      expect(Payments::ItemInvoice.where(item_id: batch.items.select(:id)).pluck(:active)).to all(be(false))
      expect([ acme_invoice, beta_invoice ].map { |i| i.reload.payment_status }).to all(eq("paid"))
    end

    it "does it once" do
      post_all

      expect(post_all).to be_failure
      expect(post_all[:code]).to eq(:nothing_to_post)
    end
  end

  describe "a part payment" do
    it "letters a part: the rest stays open, the invoice partly paid, and ready for a later batch" do
      part = submitted_batch({ invoice_id: acme_invoice.id, amount: 500 })
      debit!(part)

      expect(post_all(part)).to be_success

      expect(acme_invoice.reload.status).to eq("partially_paid")
      expect(Payments::OpenAmounts.rests([ acme_invoice ])[acme_invoice.id]).to eq(710)
      row = Payments::Eligibility.call(execution_date: execution).find { |r| r.invoice.id == acme_invoice.id }
      expect(row).to be_eligible
      expect(row.rest).to eq(710)
    end
  end

  describe "who and what" do
    before { debit!(batch) }

    it "wants the right to validate entries" do
      assistant = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }

      expect(post_all(user: assistant)[:code]).to eq(:not_allowed)
      expect(batch.items.map { |i| i.reload.journal_entry }).to all(be_draft)
    end

    it "with four eyes, is not the work of the person who prepared the batch, nor of the one who confirmed the debit" do
      entity.update!(four_eyes: true)
      batch.reload

      expect(post_all(user: preparer)[:code]).to eq(:own_batch)
      expect(post_all(user: exporter)).to be_failure # the entries are theirs: the usual rule of four eyes
      expect(batch.items.map { |i| i.reload.journal_entry }).to all(be_draft)
      expect(post_all(user: poster)).to be_success
    end

    it "is all or nothing: when one entry cannot be validated, none is" do
      calls = 0
      allow(Accounting::PostJournalEntry).to receive(:call).and_wrap_original do |original, **args|
        (calls += 1) == 2 ? LightService::Context.make(entry: args[:entry]).tap { |c| c.fail!("period locked") } : original.call(**args)
      end

      result = post_all

      expect(result).to be_failure
      expect(batch.items.map { |i| i.reload.journal_entry }).to all(be_draft)
      expect([ acme_invoice, beta_invoice ].map { |i| i.reload.status }).to all(eq("posted"))
    end
  end

  describe "a probable double payment" do
    it "does not letter a payment of an invoice that was settled meanwhile: the invoice is disputed, a task is made, the others are lettered" do
      debit!(batch)
      # the invoice of Acme is paid by another means before the entries are validated
      other = Accounting::JournalEntry.create!(journal: bank.journal, fiscal_year: fiscal_year, entry_date: Date.current, reference: "MANUAL-1", description: "Paid by hand", status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      manual = Accounting::JournalEntryLine.create!(journal_entry: other, account: suppliers, partner: supplier, invoice: acme_invoice, debit: 1210, credit: 0)
      Accounting::JournalEntryLine.create!(journal_entry: other, account: bank.journal.default_account, debit: 0, credit: 1210)
      Accounting::PostJournalEntry.call!(entry: other, keep_reference: true)
      Accounting::LetterLines.call(lines: [ trade_line(acme_invoice), manual.reload ]).tap { |r| raise r.message if r.failure? }

      result = post_all

      expect(result).to be_success
      expect(acme_invoice.reload.payment_status).to eq("disputed")
      expect(Accounting::Task.where(target: acme_invoice).pluck(:title).join).to match(/double payment/i)
      expect(beta_invoice.reload.status).to eq("paid")
      expect(batch.items.find_by(holder_name: "Acme Ltd").journal_entry).to be_posted # the money left the bank: the entry is validated, the debit stays open on the supplier
      expect(audit("payment_batch_double_payment_suspected").count).to eq(1)
    end
  end
end

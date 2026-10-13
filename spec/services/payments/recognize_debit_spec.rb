require "rails_helper"

# B01c §6 "Reconnaissance du lot dans le relevé" (rule 0): a debit line of the statement is recognised as the debit of a batch - a grouped line (A, A'), the line of one
# payment (B), or a batch debited but for a few payments (C). Nothing is written here; a person confirms. Never 100 on the amount alone; two batches that look alike
# are never told apart by the machine.
RSpec.describe Payments::RecognizeDebit do
  include_context "with submitted batch"

  def other_supplier(name = "Beta Corp", iban: "BE71096123456769")
    create(:partner, :supplier, name: name, iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: iban, holder_name: name, created_by: owner, first_seen_at: 90.days.ago) }
  end

  let(:batch) { submitted_batch(posted) } # 1 210.00 to Acme (BE68 5390 0754 7034)

  def recognise(line) = described_class.call(line)

  describe "a grouped line (A, A')" do
    it "is the batch at 100 when its reference says which, with the right amount in the right days" do
      line = debit_line(1210, description: "Remise #{batch.reference} 1 virement")

      proposal = recognise(line)

      expect(proposal).to have_attributes(batch: batch, score: 100, rule: "A", missing_items: [])
      expect(proposal.items).to eq(batch.items.to_a)
    end

    it "finds the reference wherever the bank puts it: the bank reference, the customer reference, the communication" do
      expect(recognise(debit_line(1210, bank_reference: batch.message_id))).to have_attributes(score: 100)
      expect(recognise(debit_line(1210, raw_data: { "customer_reference" => batch.reference }))).to have_attributes(score: 100)
      expect(recognise(debit_line(1210, structured_communication: batch.reference))).to have_attributes(score: 100)
    end

    it "is at 90 only, never 100, on the amount and the days alone" do
      batch
      expect(recognise(debit_line(1210))).to have_attributes(batch: batch, score: 90, rule: "A'")
    end

    it "keeps to the window: a day before the execution date to five open days after" do
      batch
      expect(recognise(debit_line(1210, on: execution - 1))).to have_attributes(score: 90)
      expect(recognise(debit_line(1210, on: execution + 7))).to have_attributes(score: 90) # Wed 14 + 5 open days = Wed 21
      expect(recognise(debit_line(1210, on: execution - 2))).to be_nil
      expect(recognise(debit_line(1210, on: execution + 8))).to be_nil
    end

    it "reads the value date when the line has one" do
      batch
      expect(recognise(debit_line(1210, on: execution + 20, value_date: execution))).to have_attributes(score: 90)
    end

    it "is not another amount, a credit, a line already dealt with, or another account" do
      batch
      expect(recognise(debit_line(1210.01))).to be_nil
      expect(recognise(create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution))).to be_nil
      expect(recognise(debit_line(1210, status: :reconciled))).to be_nil
      expect(recognise(debit_line(1210, bank_account: create(:bank_account)))).to be_nil
    end

    it "is told apart from another batch of the same total by the reference alone: without it, nothing is proposed" do
      first = batch
      second = submitted_batch(posted(partner: other_supplier, unit_price: 1000))

      expect(recognise(debit_line(1210))).to be_nil
      expect(recognise(debit_line(1210, description: second.reference))).to have_attributes(batch: second, score: 100)
      expect(recognise(debit_line(1210, description: first.reference))).to have_attributes(batch: first, score: 100)
    end
  end

  describe "the state of the batch" do
    it "does not take a batch that was not exported, nor one that was given up" do
      draft = batch_of(posted(partner: other_supplier, unit_price: 77))
      cancelled = submitted_batch(posted(partner: other_supplier("Gamma", iban: "BE62510007547061"), unit_price: 55))
      Payments::CancelBatch.call(batch: cancelled, user: exporter, reason: "x")
      Payments::CancelBatch.call(batch: cancelled.reload, user: exporter, reason: "x") if cancelled.reload.cancel_requested?
      Payments::ConfirmCancellation.call(batch: cancelled.reload, user: exporter)

      expect(recognise(debit_line(draft.total, description: draft.reference))).to be_nil
      expect(recognise(debit_line(cancelled.total, description: cancelled.reference))).to be_nil
    end

    it "takes a batch whose cancellation was only asked for, with a warning: the file may have been loaded" do
      batch
      Payments::CancelBatch.call(batch: batch, user: exporter, reason: "changed my mind")

      proposal = recognise(debit_line(1210, description: batch.reference))

      expect(proposal.batch).to eq(batch)
      expect(proposal.warnings).to include(:cancel_requested)
    end

    it "does not take a batch that was already debited" do
      batch.update_columns(status: Payments::Batch.statuses[:debited])

      expect(recognise(debit_line(1210, description: batch.reference))).to be_nil
    end
  end

  describe "the line of one payment (B)" do
    let(:beta) { other_supplier }
    let(:three) { submitted_batch(posted(unit_price: 1000), posted(partner: beta, unit_price: 500), posted(partner: other_supplier("Gamma", iban: "BE62510007547061"), unit_price: 200)) }
    let(:acme_item) { three.items.find_by(holder_name: "Acme Ltd") }

    it "is the batch at 100 with the end-to-end id, at 90 without it, when the amount and the account paid are the payment's" do
      with_id = recognise(debit_line(1210, counterparty_iban: "BE68539007547034", raw_data: { "customer_reference" => acme_item.end_to_end_id }))
      expect(with_id).to have_attributes(batch: three, score: 100, rule: "B")
      expect(with_id.items).to eq([ acme_item ])

      without = recognise(debit_line(1210, counterparty_iban: "BE68539007547034"))
      expect(without).to have_attributes(score: 90, rule: "B")
      expect(without.items).to eq([ acme_item ])
    end

    it "is also found by the communication of the payment" do
      expect(recognise(debit_line(1210, counterparty_iban: "BE68539007547034", description: acme_item.remittance))).to have_attributes(score: 100, rule: "B")
    end

    it "wants the account paid: the same amount to another account is nothing" do
      three
      expect(recognise(debit_line(1210, counterparty_iban: "NL91ABNA0417164300"))).to be_nil
      expect(recognise(debit_line(1210))).to be_nil
    end

    it "does not take a payment that was confirmed already" do
      acme_item.update_columns(status: Payments::Item.statuses[:confirmed])

      expect(recognise(debit_line(1210, counterparty_iban: "BE68539007547034"))).to be_nil
    end
  end

  describe "a batch debited but for a few payments (C)" do
    let(:beta) { other_supplier }
    let(:three) { submitted_batch(posted(unit_price: 1000), posted(partner: beta, unit_price: 500), posted(partner: other_supplier("Gamma", iban: "BE62510007547061"), unit_price: 200)) }

    it "is proposed at 70 with the payments that are missing, for a person to confirm" do
      missing = three.items.find_by(holder_name: "Beta Corp")
      line = debit_line(three.total - missing.amount, description: three.reference)

      proposal = recognise(line)

      expect(proposal).to have_attributes(batch: three, score: 70, rule: "C")
      expect(proposal.missing_items).to eq([ missing ])
      expect(proposal.items).to match_array(three.items - [ missing ])
    end

    it "is nothing when two sets of payments could be the missing ones" do
      twin_a = submitted_batch(posted(partner: other_supplier("Twin A", iban: "BE62510007547061"), unit_price: 100), posted(partner: other_supplier("Twin B", iban: "BE71096123456769"), unit_price: 100),
                               posted(unit_price: 1000))
      shorter = twin_a.total - twin_a.items.find_by(holder_name: "Twin A").amount

      expect(recognise(debit_line(shorter, description: twin_a.reference))).to be_nil
    end

    it "is nothing for a line that is not a batch minus some payments" do
      three
      expect(recognise(debit_line(three.total - 1, description: three.reference))).to be_nil
    end
  end
end

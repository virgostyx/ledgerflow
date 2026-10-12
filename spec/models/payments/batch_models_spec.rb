require "rails_helper"

# B01b §5: the data of a payment batch - the batch, its payments (with a snapshot of the account paid), what each pays, the holds, the profile of a bank.
# A bill is in one active batch at most (invariant I16), whatever the concurrency: the database says so.
RSpec.describe "Payment batch models" do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:bank_account) { create(:bank_account) }
  let(:partner) { create(:partner, :supplier) }
  let(:preparer) { create(:user) }
  let(:invoice) { create(:invoice, :supplier, :posted, fiscal_year: fiscal_year, partner: partner) }

  def batch(**attrs) = Payments::Batch.create!({ bank_account: bank_account, reference: "LOT-#{SecureRandom.hex(3)}", requested_execution_date: Date.current + 2, prepared_by: preparer, prepared_at: Time.current }.merge(attrs))

  def item_for(batch, amount: "100.00", invoices: [ invoice ])
    item = batch.items.create!(partner: partner, iban: "BE68539007547034", holder_name: "Acme Ltd", amount: amount, end_to_end_id: "E2E#{SecureRandom.hex(6)}", remittance: "Invoice")
    invoices.each { |inv| item.item_invoices.create!(invoice: inv, amount: amount) }
    item
  end

  describe Payments::Batch do
    it "starts as a draft, with the amounts of a batch in EUR to the cent" do
      b = batch

      expect(b).to be_draft
      expect(b.total).to eq(BigDecimal("0.00"))
      expect(b.payments_count).to eq(0)
    end

    it "has a reference that is its own within the entity" do
      batch(reference: "LOT-1")

      expect { batch(reference: "LOT-1") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "is active from the draft to the moment it is paid, or given up" do
      b = batch
      expect(Payments::Batch::ACTIVE).to include("draft", "pending_approval", "approved", "exported", "submitted", "cancel_requested")
      expect(Payments::Batch::ACTIVE).not_to include("debited", "cancelled", "partially_rejected")
      expect(b).to be_active
    end
  end

  describe Payments::Item do
    it "keeps a snapshot of the account it pays: the IBAN, encrypted, as it was when the batch was made" do
      item = item_for(batch)

      stored = Payments::Item.connection.select_value("SELECT iban FROM payment_items WHERE id = #{item.id}")
      expect(stored).not_to include("5390")
      expect(item.reload.iban).to eq("BE68539007547034")
      expect(item.masked_iban).to eq("BE68 **** **** 7034")
      expect(item).to be_included
    end

    it "has an end-to-end identifier of at most 35 characters" do
      b = batch

      expect(b.items.build(partner: partner, iban: "BE68539007547034", holder_name: "A", amount: "1.00", end_to_end_id: "X" * 36, remittance: "r")).not_to be_valid
    end
  end

  describe Payments::ItemInvoice do
    it "marks a bill as being in an active batch, and frees it when the batch is cancelled" do
      b = batch
      item_for(b)
      expect(Payments::ItemInvoice.where(invoice: invoice, active: true)).to exist

      b.update!(status: :cancelled)

      expect(Payments::ItemInvoice.where(invoice: invoice, active: true)).to be_empty
      expect(Payments::ItemInvoice.where(invoice: invoice)).to exist # the history stays
    end

    it "keeps a bill in one active batch at most, and the second one fails in the database" do
      item_for(batch)

      expect { item_for(batch) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "lets a bill go in another batch once the first is paid (a part payment leaves a rest to pay)" do
      first = batch
      item_for(first)
      first.update!(status: :debited)

      expect { item_for(batch) }.not_to raise_error
    end
  end

  describe "the sign of what a payment pays" do
    it "is positive for an invoice, and negative for a credit note netted against it" do
      item = batch.items.create!(partner: partner, iban: "BE68539007547034", holder_name: "A", amount: "50.00", end_to_end_id: "E1", remittance: "r")
      note = create(:invoice, :supplier, :posted, document_type: :credit_note, fiscal_year: fiscal_year, partner: partner)

      expect(item.item_invoices.build(invoice: invoice, amount: "-5")).not_to be_valid
      expect(item.item_invoices.build(invoice: invoice, amount: "0")).not_to be_valid
      expect(item.item_invoices.build(invoice: note, amount: "5")).not_to be_valid
      expect(item.item_invoices.build(invoice: note, amount: "-5")).to be_valid
    end
  end

  describe Payments::Hold do
    it "blocks an invoice or a whole supplier, with a reason and an author, until released" do
      hold = Payments::Hold.create!(invoice: invoice, reason: "Goods not received", created_by: preparer)

      expect(hold).to be_active
      hold.update!(released_at: Time.current)
      expect(hold).not_to be_active
      expect(Payments::Hold.new(reason: "x", created_by: preparer)).not_to be_valid # an invoice or a supplier is needed
      expect(Payments::Hold.new(partner: partner, created_by: preparer)).not_to be_valid # and a reason
    end
  end

  describe Payments::BankProfile do
    it "says which format a bank takes, and whether that was confirmed" do
      profile = Payments::BankProfile.create!(name: "Crelan", format_version: "pain.001.001.03")

      expect(profile).to have_attributes(encoding: "UTF-8", format_verified: false, coda_verified: false, max_payments: nil)
    end
  end
end

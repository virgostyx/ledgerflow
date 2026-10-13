require "rails_helper"

# B01c §6 "Indicateurs et rapports": the share of batches recognised from the statement, the mean delay between the due date and the payment, the late payments, the amount
# returned; and the export "Paiements exécutés" with the detail per invoice, for the auditor.
RSpec.describe "Payment indicators and the export of executed payments" do
  include_context "with submitted batch"

  let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:range) { (Date.current - 30)..(Date.current + 30) }

  def debited_by_statement(invoice)
    batch = submitted_batch(invoice)
    Payments::ConfirmDebit.call(batch: batch, user: exporter, transaction: debit_line(batch.total, description: batch.reference, bank_reference: "STMT-#{batch.id}"), items: batch.items.to_a).tap { |r| raise r.message if r.failure? }
    Payments::PostBatchPayments.call(batch: batch.reload, user: poster).tap { |r| raise r.message if r.failure? }
    batch.reload
  end

  def debited_by_hand(invoice)
    batch = submitted_batch(invoice)
    Payments::ConfirmDebit.manual(batch: batch, user: exporter, reason: "Phone", date: execution, bank_reference: "HAND-#{batch.id}").tap { |r| raise r.message if r.failure? }
    batch.reload
  end

  let(:beta) { create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago) } }

  describe Payments::Indicators do
    it "tells the share of batches debited that were recognised from the statement, the late payments and the delay" do
      on_time = posted(unit_price: 1000, due: execution + 5)
      late = posted(partner: beta, unit_price: 500, due: execution - 10)
      debited_by_statement(on_time)
      debited_by_hand(late)

      result = described_class.call(range)

      expect(result).to have_attributes(batches: 2, recognised_from_statement: 1, recognition_rate: BigDecimal("0.5"), late_payments: 1)
      expect(result.late_amount).to eq(605)
      expect(result.mean_days_late).to eq(BigDecimal("2.5")) # (5 days early, 10 days late) / 2: positive is late
    end

    it "adds up what came back" do
      invoice = posted(unit_price: 1000)
      batch = debited_by_statement(invoice)
      credit = create(:bank_transaction, bank_account: bank, amount: 1210, transaction_date: execution + 2, counterparty_iban: "BE68539007547034")
      Payments::RegisterReturn.call(item: batch.items.first, transaction: credit, user: exporter, reason: "Returned").tap { |r| raise r.message if r.failure? }

      expect(described_class.call(range).returned_amount).to eq(1210)
    end

    it "is empty, not an error, when nothing was debited" do
      expect(described_class.call(range)).to have_attributes(batches: 0, recognition_rate: nil, mean_days_late: nil, late_payments: 0, returned_amount: 0)
    end
  end

  describe Payments::ExecutedPayments do
    it "lists each invoice paid with its batch, payment, entry and statement, for the period" do
      invoice = posted(unit_price: 1000)
      batch = debited_by_statement(invoice)
      item = batch.items.first

      result = described_class.call(range)
      row = result.rows.sole

      expect(row).to have_attributes(batch_reference: batch.reference, supplier: "Acme Ltd", end_to_end_id: item.end_to_end_id, invoice_number: invoice.invoice_number, amount: 1210,
                                     entry_reference: item.journal_entry.reference, statement_reference: "STMT-#{batch.id}", masked_iban: "BE68 **** **** 7034")
      expect(result.totals).to include(amount: 1210)
    end

    it "gives a CSV and an XLSX with the same rows, the IBAN masked" do
      debited_by_statement(posted(unit_price: 1000))
      result = described_class.call(range)

      csv = Reports::Exporters::Csv.call(result, columns: described_class::COLUMNS)
      expect(csv).to include("Acme Ltd").and include("BE68 **** **** 7034")
      expect(csv).not_to include("BE68539007547034")
      expect(Reports::Exporters::Xlsx.call(result, columns: described_class::COLUMNS, title: "Executed payments")).to start_with("PK")
    end

    it "leaves out what was not debited" do
      submitted_batch(posted(unit_price: 1000))

      expect(described_class.call(range).rows).to be_empty
    end
  end
end

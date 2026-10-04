require "rails_helper"

# F06 step 3, acceptance criterion 5 (docs/dev/features/spec.md §9): the payment reference of a received invoice lets the bank matching find its
# payment by the structured communication (rule 1 of F02) and the assisted lettering propose the pair with a score of 100 (rule 1 of F04).
RSpec.describe "The payment reference of a received invoice" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:bank_account) { create(:bank_account) }
  let(:supplier) { create(:partner, partner_type: :supplier, name: "Fournisseur SA") }
  let(:digits) { Accounting::StructuredCommunication.for_id(123_456) }
  let(:reference) { Accounting::StructuredCommunication.display(digits) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:od) { create(:journal, :cash) }

  def supplier_invoice(payment_reference: reference, total: 121, number: "SUP-1")
    invoice = create(:invoice, :posted, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, journal: purchase_journal, supplier_reference: number, payment_reference: payment_reference)
    invoice.update_columns(total_incl_vat: total, subtotal_excl_vat: total, vat_amount: 0)
    invoice
  end

  def payment(amount: -121, communication: digits) = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s), structured_communication: communication, description: "Payment")

  describe "the bank matching (F02, rule 1)" do
    it "matches a payment whose structured communication is the payment reference, for the same amount, with a score of 100" do
      invoice = supplier_invoice

      suggestion = Accounting::MatchBankTransaction.call(transaction: payment)

      expect(suggestion).to have_attributes(kind: :supplier_invoice, target: invoice, score: 100, rule: 1, confidence: :high)
    end

    it "finds it in the description too, written with the plus signs" do
      invoice = supplier_invoice
      tx = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal("-121"), structured_communication: nil, description: "Virement #{reference}")

      expect(Accounting::MatchBankTransaction.call(transaction: tx)).to have_attributes(target: invoice, rule: 1)
    end

    it "does not match another amount by this rule" do
      supplier_invoice

      expect(Accounting::MatchBankTransaction.call(transaction: payment(amount: -100))&.rule).not_to eq(1)
    end

    it "does not guess between two invoices that carry the same reference" do
      supplier_invoice(number: "SUP-1")
      supplier_invoice(number: "SUP-2")

      expect(Accounting::MatchBankTransaction.call(transaction: payment)&.rule).not_to eq(1)
    end

    it "ignores a reference that is not a valid structured communication" do
      supplier_invoice(payment_reference: "REF 2026/001")

      expect(Accounting::MatchBankTransaction.call(transaction: payment)).to be_nil
    end
  end

  describe "the assisted lettering (F04, rule 1)" do
    def line(debit: 0, credit: 0, invoice: nil, communication: nil)
      ApplicationRecord.transaction do
        entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 20)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
        create(:bank_transaction, journal_entry: entry, structured_communication: communication) if communication
        create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, invoice: invoice, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
      end
    end

    it "proposes the invoice and its payment with a score of 100 when the payment carries the reference" do
      invoice = supplier_invoice
      owed = line(credit: 121, invoice: invoice)
      paid = line(debit: 121, communication: digits)

      Accounting::SuggestLetterings.call

      suggestion = Accounting::LetteringSuggestion.proposed.sole
      expect(suggestion).to have_attributes(rule: 1, score: 100, line_ids: [ owed.id, paid.id ].sort)
    end
  end
end

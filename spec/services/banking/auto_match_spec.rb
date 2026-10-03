require "rails_helper"

# F02: what the engine does with each pending line. 100 on a customer invoice: a draft payment entry (validated only when the
# entity asks), 75 to 99: a suggestion kept for a person, below: nothing. A bank rule may ask for a draft too.
RSpec.describe Banking::AutoMatch do
  include_context "with_open_fiscal_year"

  let!(:bank_gl)     { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:receivable)  { create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) }
  let!(:fees)        { create(:account, code: "651100", label_fr: "Frais bancaires") }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account) { create(:bank_account, journal: bank_journal) }
  let(:partner) { create(:partner, name: "DUPONT ET FILS SPRL", iban: CodaBuilder.iban("091012345678")) }
  let(:invoice) { create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("1210")) } }

  def structured(target) = Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(target.id))
  def line(amount, **attrs) = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s), **attrs)
  def run(*lines) = described_class.call(transactions: lines)

  describe "an exact match (score 100)" do
    let!(:tx) { line(1210, description: structured(invoice)) }

    it "books a draft payment entry and marks the line matched, the invoice staying unpaid until validation" do
      run(tx)

      expect(tx.reload).to be_matched
      expect(tx.journal_entry).to be_draft
      expect(invoice.reload).to be_posted
      expect(tx.match_data).to include("rule" => 1, "score" => 100, "auto" => true, "kind" => "invoice", "target_id" => invoice.id)
    end

    it "audits the automatic match" do
      run(tx)

      expect(Accounting::AuditLog.where(action: "bank_match_auto", auditable_id: tx.id).sole.payload).to include("rule" => 1, "score" => 100)
    end

    it "validates the entry when the entity asks for it, which settles the line and pays the invoice" do
      entity.update!(auto_post_exact_bank_matches: true)

      run(tx)

      expect(tx.reload).to be_reconciled
      expect(tx.journal_entry).to be_posted
      expect(invoice.reload).to be_paid
    end

    it "counts what it did" do
      result = run(tx)

      expect([ result[:drafted], result[:suggested], result[:untouched] ]).to eq([ 1, 0, 0 ])
    end
  end

  describe "a good but not exact match (75 to 99)" do
    it "keeps a suggestion on the line and books nothing" do
      invoice
      tx = line(1210, counterparty_iban: partner.iban, description: "x")

      result = run(tx)

      expect(tx.reload).to be_pending
      expect(tx.journal_entry).to be_nil
      expect(tx.match_data).to include("kind" => "invoice", "score" => 90, "rule" => 3, "target_id" => invoice.id)
      expect(result[:suggested]).to eq(1)
    end

    it "keeps the ids of a grouped payment" do
      a = create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("100")) }
      b = create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("250")) }
      tx = line(350, counterparty_iban: partner.iban)

      run(tx)

      expect(tx.reload.match_data).to include("kind" => "invoices", "target_ids" => contain_exactly(a.id, b.id), "score" => 80)
    end

    it "does not book a partial payment announced by its structured communication, only suggests it" do
      tx = line(500, description: structured(invoice))

      run(tx)

      expect(tx.reload).to be_pending
      expect(tx.match_data).to include("score" => 80, "rule" => 1)
    end
  end

  describe "nothing to say" do
    it "leaves a line alone and says so" do
      invoice
      tx = line(77, description: "something else")

      result = run(tx)

      expect(tx.reload).to be_pending
      expect(tx.match_data).to eq({})
      expect(result[:untouched]).to eq(1)
    end

    it "forgets an old suggestion that no longer holds" do
      tx = line(77, description: "x", match_data: { "kind" => "invoice", "score" => 90, "target_id" => 0 })

      run(tx)

      expect(tx.reload.match_data).to eq({})
    end

    it "skips a line that is already matched, reconciled or ignored" do
      invoice
      ignored = line(1210, description: structured(invoice), status: :ignored)

      run(ignored)

      expect(ignored.reload).to be_ignored
      expect(ignored.journal_entry).to be_nil
    end
  end

  describe "a bank rule" do
    let(:rule_attrs) { { name: "Bank fees", condition_type: "contains", condition_value: "frais de tenue", account: fees } }

    it "books a draft entry on the account of the rule when it asks for it" do
      Accounting::BankRule.create!(rule_attrs.merge(action: "book_draft"))
      tx = line(-12.5, description: "FRAIS DE TENUE DE COMPTE")

      run(tx)

      expect(tx.reload).to be_matched
      expect(tx.journal_entry).to be_draft
      expect(tx.journal_entry.lines.find_by(account: fees).debit).to eq(BigDecimal("12.5"))
      expect(tx.match_data).to include("kind" => "rule", "rule" => 6)
    end

    it "only proposes it when it does not" do
      Accounting::BankRule.create!(rule_attrs.merge(action: "propose", score: 85))
      tx = line(-12.5, description: "FRAIS DE TENUE DE COMPTE")

      run(tx)

      expect(tx.reload).to be_pending
      expect(tx.match_data).to include("kind" => "rule", "score" => 85)
    end
  end

  describe "a line that cannot be booked" do
    it "does not stop the others, and says what went wrong" do
      invoice
      good = line(1210, description: structured(invoice))
      other = create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("40")) }
      bad = line(40, description: structured(other))
      allow(Accounting::AcceptBankSuggestion).to receive(:call).and_wrap_original do |original, **kwargs|
        raise "boom" if kwargs[:transaction] == bad

        original.call(**kwargs)
      end

      result = run(bad, good)

      expect(good.reload).to be_matched
      expect(bad.reload).to be_pending
      expect(result[:problems].join).to include("boom")
    end
  end
end

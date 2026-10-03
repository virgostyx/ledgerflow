require "rails_helper"

# F04 §7: the six rules, their scores, and the fingerprint that keeps a rejected group from coming back.
RSpec.describe Accounting::SuggestLetterings do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:supplier) { create(:partner, :supplier) }
  let(:od)       { create(:journal, :cash) }

  def line(debit: 0, credit: 0, partner: supplier, date: fiscal_year.start_date + 20, reference: nil, invoice: nil, communication: nil)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: date, **(reference ? { reference: reference } : {}))
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:bank_transaction, journal_entry: entry, structured_communication: communication) if communication
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, invoice: invoice,
                                  debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  def suggestions = Accounting::LetteringSuggestion.proposed.order(:score)
  def rules_for(*lines) = Accounting::LetteringSuggestion.where(line_ids: lines.map(&:id).sort).pluck(:rule)

  describe "rule 1: opposite pair, same amount, same reference" do
    it "scores 100 when a payment carries the reference of the invoice" do
      invoice_line = line(credit: 121, reference: "FAC-2026-0042")
      payment      = line(debit: 121, communication: "fac 2026 0042")
      described_class.call

      expect(suggestions.sole).to have_attributes(rule: 1, score: 100, line_ids: [ invoice_line.id, payment.id ].sort, partner_id: supplier.id)
    end

    it "does not trust an ambiguous pairing: two identical invoices and one payment fall back to rule 3" do
      line(credit: 121, reference: "FAC-2026-0042")
      line(debit: 121, communication: "FAC-2026-0042")
      line(debit: 121, communication: "FAC-2026-0042")
      described_class.call

      expect(suggestions.map(&:score)).not_to include(100)
    end

    it "ignores references too short to mean anything" do
      line(credit: 121, reference: "A1")
      line(debit: 121, communication: "A1")
      described_class.call

      expect(suggestions.sole.rule).to eq(3)
    end
  end

  describe "rule 2: invoice and credit note of the same document" do
    it "scores 95" do
      invoice = create(:invoice, :posted, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
      note    = create(:invoice, :posted, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year,
                                          document_type: :credit_note, credited_invoice: invoice)
      a = line(credit: 50, invoice: invoice)
      b = line(debit: 50, invoice: note)
      described_class.call

      expect(rules_for(a, b)).to eq([ 2 ])
    end
  end

  describe "rule 3: opposite pair, same amount, nearest dates" do
    it "scores 90 and pairs each line with the closest date" do
      a1 = line(credit: 80, date: fiscal_year.start_date + 10)
      a2 = line(credit: 80, date: fiscal_year.start_date + 60)
      p1 = line(debit: 80, date: fiscal_year.start_date + 12)
      p2 = line(debit: 80, date: fiscal_year.start_date + 58)
      described_class.call

      expect(rules_for(a1, p1)).to eq([ 3 ])
      expect(rules_for(a2, p2)).to eq([ 3 ])
      expect(rules_for(a1, p2)).to be_empty
    end

    it "never mixes partners" do
      line(credit: 80)
      line(debit: 80, partner: create(:partner, :supplier))
      described_class.call

      expect(suggestions).to be_empty
    end
  end

  describe "rule 4: balanced group" do
    it "scores 85 when three invoices and two payments settle to zero" do
      lines = [ line(credit: 100), line(credit: 50), line(credit: 30), line(debit: 120), line(debit: 60) ]
      described_class.call

      expect(rules_for(*lines)).to eq([ 4 ])
    end
  end

  describe "rule 5: one line against a combination" do
    it "scores 80 for a payment of three invoices" do
      invoices = [ line(credit: 100), line(credit: 40), line(credit: 10) ]
      payment  = line(debit: 150)
      line(credit: 7) # an unrelated open line keeps rule 4 out
      described_class.call

      expect(rules_for(*invoices, payment)).to eq([ 5 ])
    end

    it "does not search beyond eight lines" do
      nine = Array.new(9) { line(credit: 10) }
      line(debit: 90)
      line(credit: 7)
      described_class.call

      expect(rules_for(*nine, Accounting::JournalEntryLine.where(debit: 90).first)).to be_empty
    end
  end

  describe "rule 6: rounding" do
    it "scores 70 for a pair that differs by no more than the tolerance" do
      a = line(credit: 100.00)
      b = line(debit: 99.97)
      described_class.call

      expect(rules_for(a, b)).to eq([ 6 ])
    end

    it "proposes nothing above the tolerance" do
      line(credit: 100.00)
      line(debit: 99.90)
      described_class.call

      expect(suggestions).to be_empty
    end
  end

  describe "life of a suggestion" do
    let!(:a) { line(credit: 121, reference: "FAC-2026-0042") }
    let!(:b) { line(debit: 121, communication: "FAC-2026-0042") }

    it "is idempotent" do
      2.times { described_class.call }

      expect(Accounting::LetteringSuggestion.count).to eq(1)
    end

    it "keeps a rejected group out until one of its lines changes" do
      described_class.call
      suggestions.sole.rejected!
      described_class.call
      expect(suggestions).to be_empty

      [ a, b ].each { |l| l.update_columns(debit: l.debit.positive? ? 130 : 0, credit: l.credit.positive? ? 130 : 0, amount_residual: 130) }
      described_class.call

      expect(suggestions.sole.line_ids).to eq([ a.id, b.id ].sort)
    end

    it "forgets a proposal whose lines are lettered meanwhile" do
      described_class.call
      Accounting::LetterLines.call(lines: [ a, b ])
      described_class.call

      expect(suggestions).to be_empty
    end

    it "skips lines already partly settled by allocations" do
      Accounting::AllocateLines.call(lines: [ a, line(debit: 60) ])
      described_class.call

      expect(suggestions).to be_empty
    end
  end
end

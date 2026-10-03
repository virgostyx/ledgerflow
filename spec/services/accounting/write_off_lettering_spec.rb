require "rails_helper"

# F04 §7: a rounding difference within the entity's tolerance is booked on a dedicated account by a draft entry, and the lettering
# is complete once that entry is validated.
RSpec.describe Accounting::WriteOffLettering do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)     { create(:user, role: :accountant) }
  let(:supplier) { create(:partner, :supplier) }
  let(:od)       { create(:journal, :cash) }
  let!(:misc)    { create(:journal, journal_type: :misc) }
  let!(:loss)    { create(:account, code: "658100", label_fr: "Rounding (charge)", account_class: 6, entity: entity) }
  let!(:gain)    { create(:account, code: "758100", label_fr: "Rounding (income)", account_class: 7, entity: entity) }

  def line(debit: 0, credit: 0)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 20)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  let!(:invoice_line) { line(credit: 100.00) }
  let!(:payment)      { line(debit: 99.97) }

  def write_off(lines = [ invoice_line, payment ]) = described_class.call(lines: lines, user: user)

  describe "the draft" do
    it "books a difference in our favour (we paid less) as an income" do
      result = write_off
      entry = result[:entry]

      expect(result).to be_success
      expect(entry).to be_draft
      expect(entry.lines.find_by(account: account_440)).to have_attributes(debit: BigDecimal("0.03"), credit: 0, partner_id: supplier.id)
      expect(entry.lines.find_by(account: gain)).to have_attributes(credit: BigDecimal("0.03"), debit: 0)
    end

    it "books a difference against us (we paid more) as a charge" do
      invoice = line(credit: 100.00)
      over    = line(debit: 100.04)
      entry = write_off([ invoice, over ])[:entry]

      expect(entry.lines.find_by(account: account_440)).to have_attributes(credit: BigDecimal("0.04"))
      expect(entry.lines.find_by(account: loss)).to have_attributes(debit: BigDecimal("0.04"))
    end

    it "leaves the lines open until the draft is validated" do
      write_off

      expect(invoice_line.reload.lettering_id).to be_nil
      expect(payment.reload.lettering_id).to be_nil
    end

    it "refuses to book the same lines twice" do
      write_off

      expect(write_off).to be_failure
      expect(Accounting::LetteringWriteOff.count).to eq(1)
    end
  end

  describe "validating the draft" do
    it "letters the lines with the adjustment line, as a write-off by the same person" do
      entry = write_off[:entry]
      Accounting::PostJournalEntry.call!(entry: entry)

      lettering = Accounting::Lettering.find(invoice_line.reload.lettering_id)
      expect(lettering).to have_attributes(kind: "write_off", lettered_by_id: user.id, auto: false)
      expect(lettering.lines.pluck(:id)).to match_array([ invoice_line.id, payment.id, entry.lines.find_by(account: account_440).id ])
      expect(Accounting::LetteringWriteOff.sole.completed_at).to be_present
    end

    it "leaves the lines open, without undoing the validation, when they cannot be lettered any more" do
      entry = write_off[:entry]
      payment.update_columns(lettering_id: create(:lettering, account: account_440).id)

      expect(Accounting::PostJournalEntry.call(entry: entry)).to be_success
      expect(entry.reload).to be_posted
      expect(invoice_line.reload.lettering_id).to be_nil
    end
  end

  describe "refusals" do
    it "refuses a difference above the tolerance" do
      big = line(debit: 99.90)

      expect(write_off([ invoice_line, big ])).to be_failure
    end

    it "refuses a lettering that balances (an ordinary lettering does that)" do
      exact = line(debit: 100.00)

      expect(write_off([ invoice_line, exact ])).to be_failure
    end

    it "refuses while the entity has no rounding accounts" do
      loss.destroy!
      gain.destroy!

      expect(write_off).to be_failure
    end

    it "refuses lines of different partners" do
      other = line(debit: 99.97).tap { |l| l.update_columns(partner_id: create(:partner, :supplier).id) }

      expect(write_off([ invoice_line, other ])).to be_failure
    end
  end

  describe "accepting a rounding suggestion (rule 6)" do
    it "books the draft and marks the suggestion accepted" do
      Accounting::SuggestLetterings.call
      suggestion = Accounting::LetteringSuggestion.proposed.sole
      expect(suggestion.rule).to eq(6)

      result = Accounting::AcceptLetteringSuggestion.call(suggestion: suggestion, user: user)

      expect(result).to be_success
      expect(suggestion.reload).to be_accepted
      expect(Accounting::LetteringWriteOff.count).to eq(1)
    end

    it "proposes the lines again when the draft is deleted" do
      Accounting::SuggestLetterings.call
      suggestion = Accounting::LetteringSuggestion.proposed.sole
      entry = Accounting::AcceptLetteringSuggestion.call(suggestion: suggestion, user: user)[:entry]

      Accounting::SuggestLetterings.call
      expect(Accounting::LetteringSuggestion.proposed).to be_empty

      entry.lines.destroy_all
      entry.destroy!
      Accounting::SuggestLetterings.call

      expect(Accounting::LetteringSuggestion.proposed.sole.rule).to eq(6)
    end
  end
end

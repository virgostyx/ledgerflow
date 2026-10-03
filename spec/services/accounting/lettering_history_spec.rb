require "rails_helper"

# F04: who lettered and unlettered what, when and why (history per line); an unlettering needs a reason, and a locked period asks more;
# lettering across partners needs its own right and a reason; two people lettering the same line: one wins.
RSpec.describe "Lettering history, reasons and rights (F04)" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let(:supplier) { create(:partner, :supplier) }
  let(:other)    { create(:partner, :supplier) }
  let(:od)       { create(:journal, :cash) }

  # Each entry balances (with a line on 604000): the double-entry check bites at commit, which the concurrency example really does.
  def line(debit: 0, credit: 0, partner: supplier, date: fiscal_year.start_date + 20, currency: nil)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: date)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s),
                                  **(currency ? { currency: currency, amount_currency: BigDecimal((debit + credit).to_s), exchange_rate: 1 } : {}))
    end
  end

  let!(:credit_line) { line(credit: 121) }
  let!(:debit_line)  { line(debit: 121) }

  def letter(**options) = Accounting::LetterLines.call(lines: [ credit_line, debit_line ], user: accountant, **options)
  def events(line) = Accounting::LetteringEvent.where(line_id: line.id).order(:id)

  describe "the history of a line" do
    it "records the lettering, with its code, who did it, and whether it was automatic" do
      lettering = letter[:lettering]

      expect(events(credit_line).sole).to have_attributes(action: "letter", code: lettering.code, user_id: accountant.id, auto: false, reason: nil)
      expect(events(debit_line).count).to eq(1)
      expect(lettering).to have_attributes(kind: "full", auto: false)
    end

    it "marks an automatic lettering as such" do
      lettering = letter(auto: true, user: nil)[:lettering]

      expect(lettering).to be_auto
      expect(events(credit_line).sole).to have_attributes(auto: true, user_id: nil)
    end

    it "keeps the unlettering, with its reason, after the lettering itself is gone" do
      lettering = letter[:lettering]
      code = lettering.code

      Accounting::UnletterLines.call(lettering: lettering, user: accountant, reason: "Wrong supplier")

      expect(Accounting::Lettering.exists?(lettering.id)).to be false
      expect(events(credit_line).pluck(:action, :code, :reason, :user_id)).to eq([ [ "letter", code, nil, accountant.id ], [ "unletter", code, "Wrong supplier", accountant.id ] ])
    end
  end

  describe "an unlettering" do
    it "needs a reason, and changes nothing without one" do
      lettering = letter[:lettering]

      result = Accounting::UnletterLines.call(lettering: lettering, user: accountant, reason: " ")

      expect(result).to be_failure
      expect(result.message).to match(/reason/i)
      expect(credit_line.reload.lettering_id).to eq(lettering.id)
    end

    it "is allowed for any user in an open period" do
      expect(Accounting::UnletterLines.call(lettering: letter[:lettering], user: accountant, reason: "x")).to be_success
    end

    it "is refused inside a locked period to whoever lacks the right, and allowed to the owner, who has it" do
      lettering = letter[:lettering]
      create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month)

      refused = Accounting::UnletterLines.call(lettering: lettering, user: accountant, reason: "x")
      expect(refused).to be_failure
      expect(refused.message).to match(/locked/i)
      expect(credit_line.reload.lettering_id).to eq(lettering.id)

      expect(Accounting::UnletterLines.call(lettering: lettering, user: owner, reason: "Correction agreed")).to be_success
    end

    it "does not stop a lettering inside a locked period (it changes no amount), which is logged all the same" do
      create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month)

      expect(letter).to be_success
      expect(events(credit_line)).to be_present
    end
  end

  describe "lettering across partners" do
    let!(:foreign_debit) { line(debit: 121, partner: other) }

    def cross(**options) = Accounting::LetterLines.call(lines: [ credit_line, foreign_debit ], **options)

    it "is refused by default" do
      expect(cross(user: accountant)).to be_failure
    end

    it "is allowed with the right and a reason, and records the reason on the lettering and on each line" do
      result = cross(user: accountant, cross_partner: true, reason: "Payment booked on the wrong supplier")

      expect(result).to be_success
      expect(result[:lettering]).to have_attributes(partner_id: nil, reason: "Payment booked on the wrong supplier")
      expect(events(foreign_debit).sole.reason).to eq("Payment booked on the wrong supplier")
    end

    it "needs the reason" do
      expect(cross(user: accountant, cross_partner: true)).to be_failure
    end

    it "needs the right: an assistant does not have it" do
      expect(cross(user: assistant, cross_partner: true, reason: "x")).to be_failure
    end
  end

  describe "the same line lettered twice at the same moment", :concurrency do
    it "lets one succeed and refuses the other" do
      results = concurrently(
        -> { Accounting::LetterLines.call(lines: Accounting::JournalEntryLine.where(id: [ credit_line.id, debit_line.id ]).to_a, user: accountant) },
        -> { Accounting::LetterLines.call(lines: Accounting::JournalEntryLine.where(id: [ credit_line.id, debit_line.id ]).to_a, user: owner) },
        entity: entity
      )

      expect(results.count(&:success?)).to eq(1)
      expect(Accounting::Lettering.count).to eq(1)
      expect(Accounting::LetteringEvent.where(action: "letter").count).to eq(2) # one per line, once
    end
  end

  describe "the residual of a line" do
    it "is only ever written by JournalEntryLine.resync_amount_residual! (spec: no other code modifies it)" do
      writers = Dir["app/**/*.rb"].reject { |f| f.end_with?("journal_entry_line.rb") }.select do |file|
        File.read(file).lines.any? { |l| l =~ /amount_residual\s*(=[^=]|:)|update_all\(.*amount_residual|update_columns\(.*amount_residual/ && l !~ /^\s*#/ }
      end

      expect(writers).to be_empty
    end
  end
end

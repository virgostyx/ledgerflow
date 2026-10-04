require "rails_helper"

# F04 §7 criterion 8: I4 (aged balance = balance of the collective account) stays green after any lettering operation. Random sequences
# of every operation (total lettering, partial allocation, removal, unlettering, rounding entry, accepted suggestion), refused or not:
# after each one, the aged balance equals the account, and the residual of every line is what its lettering and allocations say.
# A failure prints the seed, which replays the sequence.
RSpec.describe "Invariant I4 — after lettering operations", type: :invariant do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)    { create(:user, role: :accountant) }
  let(:journal) { create(:journal, :cash) }
  let!(:misc)   { create(:journal, journal_type: :misc) }
  let!(:loss)   { create(:account, code: "658100", label_fr: "Rounding (charge)", account_class: 6, entity: entity) }
  let!(:gain)   { create(:account, code: "758100", label_fr: "Rounding (income)", account_class: 7, entity: entity) }
  let(:partners) { create_list(:partner, 3, :supplier) }

  before { account_440.update!(normal_balance: :credit) } # as in the chart: a supplier balance is a credit

  def line(debit: 0, credit: 0, partner:, date:)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year, entry_date: date)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  def open_lines = Accounting::JournalEntryLine.where(account: account_440, lettering_id: nil).joins(:journal_entry).merge(Accounting::JournalEntry.posted).to_a

  def aged_total = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: fiscal_year.end_date).call).total

  def account_balance
    Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: fiscal_year.end_date).call.find { |r| r.code == "440000" }&.balance || BigDecimal("0")
  end

  # What amount_residual must be, rebuilt without it: 0 once lettered, else debit + credit less what the allocations settle.
  def expected_residual(l)
    return BigDecimal("0") if l.lettering_id

    l.debit + l.credit - Accounting::LineAllocation.where(debit_line_id: l.id).or(Accounting::LineAllocation.where(credit_line_id: l.id)).sum(:amount)
  end

  def operate(rng)
    lines = open_lines
    return if lines.empty?

    mine = lines.group_by(&:partner_id).values.sample(random: rng)
    case rng.rand(7)
    when 0 then Accounting::LetterLines.call(lines: mine.sample(rng.rand(2..4), random: rng), user: user)
    when 1
      credit = mine.find(&:credit?) and debit = mine.find(&:debit?)
      Accounting::AllocateLines.call(lines: [ credit, debit ]) if credit && debit
    when 2 then (allocation = Accounting::LineAllocation.all.sample(random: rng)) && Accounting::RemoveAllocation.call(allocation: allocation)
    when 3 then (lettering = Accounting::Lettering.all.sample(random: rng)) && Accounting::UnletterLines.call(lettering: lettering, reason: "random", user: user)
    when 4
      result = Accounting::WriteOffLettering.call(lines: mine.sample(2, random: rng), user: user)
      Accounting::PostJournalEntry.call(entry: result[:entry]) if result.success?
    when 5
      Accounting::SuggestLetterings.call
      (suggestion = Accounting::LetteringSuggestion.proposed.to_a.sample(random: rng)) && Accounting::AcceptLetteringSuggestion.call(suggestion: suggestion, user: user)
      Accounting::LetteringWriteOff.pending.each { |w| Accounting::PostJournalEntry.call(entry: w.journal_entry) } if rng.rand(2).zero?
    else Accounting::LetterLines.call(lines: lines.sample(2, random: rng), user: user)
    end
  end

  # criterion 5: unlettering restores the residuals and R04 (the aged balance) to what they were before the lettering
  it "restores the residuals and the aged balance when a lettering is undone" do
    a = line(credit: 200, partner: partners.first, date: fiscal_year.start_date + 5)
    b = line(debit: 200, partner: partners.first, date: fiscal_year.start_date + 9)
    residuals = [ a, b ].to_h { |l| [ l.id, l.amount_residual ] }
    before = Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: fiscal_year.end_date).call.map(&:to_h)

    lettering = Accounting::LetterLines.call(lines: [ a, b ], user: user)[:lettering]
    expect(a.reload.amount_residual).to eq(0)
    expect(Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: fiscal_year.end_date).call).to be_empty

    Accounting::UnletterLines.call(lettering: lettering, reason: "entered in error", user: user)

    expect([ a, b ].to_h { |l| [ l.id, l.reload.amount_residual ] }).to eq(residuals)
    expect(Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: fiscal_year.end_date).call.map(&:to_h)).to eq(before)
  end

  [ 1, 2, 3 ].each do |seed|
    it "holds after every operation of a random sequence (seed #{seed})" do
      rng = Random.new(seed)
      partners.each do |partner|
        3.times do |i|
          amount = BigDecimal(rng.rand(50..400).to_s)
          date = fiscal_year.start_date + rng.rand(1..300)
          line(credit: amount, partner: partner, date: date)
          line(debit: amount, partner: partner, date: date + rng.rand(1..20)) if i < 2
          line(debit: amount - BigDecimal("0.03"), partner: partner, date: date + 5) if i == 2
        end
      end

      30.times do |step|
        operate(rng)

        expect(aged_total).to eq(account_balance), "seed #{seed}, step #{step}: aged balance #{aged_total} != account #{account_balance}"
        Accounting::JournalEntryLine.where(account: account_440).find_each do |l|
          expect(l.amount_residual).to eq(expected_residual(l)), "seed #{seed}, step #{step}: line #{l.id} residual #{l.amount_residual} != #{expected_residual(l)}"
        end
      end
      expect(Accounting::LetteringEvent.where(action: %w[letter unletter]).distinct.count(:action)).to eq(2), "seed #{seed}: the sequence did not letter and unletter"
      expect(Accounting::Lettering.count + Accounting::LineAllocation.count).to be_positive
    end
  end
end

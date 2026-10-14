require "rails_helper"

# B03a: after any sequence of operations - entries validated, reversed, lettered, settled in part, unlettered, accounts and partners renamed - the history reproduces
# exactly every snapshot taken along the way. A snapshot is the trial balance, the aged balance, the open lines and a ledger, read at an instant; read again afterwards with
# `known_at` set to that instant they must be the same (and the same as what the books said, in the present, at that instant). The seed of a failing sequence is in the message: replay it.
#
#  I14. The books known at an instant never change afterwards (the reconstruction of the past is stable).
#  I14b. For every account and two instants T1 < T2, the variation of the balance known between them is the sum of the lines validated between them (specification §2.3).
RSpec.describe "Invariant I14 - the history reproduces the past after random sequences" do
  include_context "with_open_fiscal_year"

  seeds = (1..10).to_a
  operations = 25

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:partners) { [ create(:partner, name: "Alice"), create(:partner, name: "Bob") ] }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(lines, date: Date.current - 3)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: "I14-#{SecureRandom.hex(4)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    made = lines.map { |attrs| create(:journal_entry_line, journal_entry: entry, **attrs) }
    entry.post!
    next_posting_instant
    [ entry, made ]
  end

  def customer_line(rng, state)
    amount = BigDecimal([ 25, 60, 100, 250 ].sample(random: rng).to_s)
    side = rng.rand(3).zero? ? :credit : :debit
    other = side == :debit ? :credit : :debit
    partner = partners.sample(random: rng)
    entry, lines = post_entry([ { account: customer_account, partner: partner, side => amount, other => 0 }, { account: revenue, other => amount, side => 0 } ])
    state[:entries] << entry
    state[:customer_lines] << lines.first
  end

  def expense_entry(rng, state)
    amount = BigDecimal([ 10, 40, 90 ].sample(random: rng).to_s)
    entry, = post_entry([ { account: expense, debit: amount, credit: 0 }, { account: revenue, debit: 0, credit: amount } ])
    state[:entries] << entry
  end

  def settle(rng, state)
    lines = state[:customer_lines].map(&:reload).select { |l| l.partner_id && l.lettering_id.nil? }.group_by(&:partner_id).values.select { |g| g.any? { |l| l.debit.positive? } && g.any? { |l| l.credit.positive? } }.sample(random: rng)
    return unless lines

    pair = [ lines.find { |l| l.debit.positive? }, lines.find { |l| l.credit.positive? } ]
    rng.rand(2).zero? ? Accounting::AllocateLines.call(lines: pair) : Accounting::LetterLines.call(lines: pair, user: user)
  end

  def undo(rng, state)
    if rng.rand(2).zero? && (lettering = Accounting::Lettering.all.to_a.sample(random: rng))
      Accounting::UnletterLines.call(lettering: lettering, reason: "random", user: user)
    elsif (allocation = Accounting::LineAllocation.all.to_a.sample(random: rng))
      Accounting::RemoveAllocation.call(allocation: allocation)
    end
  end

  def reverse(rng, state)
    entry = state[:entries].map(&:reload).select(&:posted?).sample(random: rng)
    Accounting::ReverseJournalEntry.call(entry: entry, reason: "random", user: user) if entry
  end

  def rename(rng)
    rng.rand(2).zero? ? expense.update!(label_fr: "Services #{rng.rand(1000)}") : partners.sample(random: rng).update!(name: "Partner #{rng.rand(1000)}")
  end

  def read(known_at)
    {
      trial_balance: Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, known_at: known_at).call.map { |r| [ r.code, r.label_fr, r.total_debit, r.total_credit ] },
      aged: Accounting::AgedBalanceQuery.new(kind: :customer, known_at: known_at).call.map { |r| [ r.partner_name, r.total ] },
      open_lines: Accounting::UnletteredLinesQuery.new(kind: :customer, known_at: known_at).call.map { |r| [ r.line_id, r.partner_name, r.residual ] }.sort_by(&:first), # the order of equal dates is not one
      ledger: Accounting::GeneralLedgerQuery.new(account: customer_account, fiscal_year: fiscal_year, known_at: known_at).call.map { |r| [ r.line_id, r.partner_name, r.lettering_code, r.running_balance ] }
    }
  end

  def totals_at(known_at) = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, known_at: known_at).call.to_h { |r| [ r.code, [ r.total_debit, r.total_credit ] ] }

  def variation(t1, t2)
    from, to = totals_at(t1), totals_at(t2)
    (from.keys | to.keys).to_h { |code| [ code, [ to.fetch(code, [ 0, 0 ]).first - from.fetch(code, [ 0, 0 ]).first, to.fetch(code, [ 0, 0 ]).last - from.fetch(code, [ 0, 0 ]).last ] ] }.reject { |_, v| v.all?(&:zero?) }
  end

  # in SQL, by the instant of validation of the entries, not by the places
  def validated_between(t1, t2)
    Accounting::JournalEntryLine.joins(:journal_entry, :account)
      .where(accounting_journal_entries: { fiscal_year_id: fiscal_year.id, status: Accounting::JournalEntry.ledger_status_values }).where("accounting_journal_entries.posted_at > ? AND accounting_journal_entries.posted_at <= ?", t1, t2)
      .group("accounting_accounts.code").pluck(Arel.sql("accounting_accounts.code"), Arel.sql("SUM(accounting_journal_entry_lines.debit)"), Arel.sql("SUM(accounting_journal_entry_lines.credit)"))
      .to_h { |code, debit, credit| [ code, [ debit, credit ] ] }.reject { |_, v| v.all?(&:zero?) }
  end

  seeds.each do |seed|
    it "reproduces every snapshot of the sequence of seed #{seed}" do
      rng = Random.new(seed)
      state = { entries: [], customer_lines: [] }
      snapshots = []
      trail = []

      operations.times do |n|
        case rng.rand(10)
        when 0..2 then customer_line(rng, state).tap { trail << "customer_line" }
        when 3 then expense_entry(rng, state).tap { trail << "expense_entry" }
        when 4..5 then settle(rng, state).tap { trail << "settle" }
        when 6 then undo(rng, state).tap { trail << "undo" }
        when 7 then reverse(rng, state).tap { trail << "reverse" }
        when 8 then rename(rng).tap { trail << "rename" }
        end
        next_posting_instant # one spec is one transaction, and a transaction has one instant of validation: each operation gets its own
        next unless n.odd?

        at = instant
        snapshots << [ at, read(nil), trail.last(3).join(" > ") ] # what the books say now, which is what they will have to say of this instant later
      end

      snapshots.each_cons(2).with_index do |((t1, *), (t2, *)), index|
        expect(variation(t1, t2)).to eq(validated_between(t1, t2)), "seed #{seed}: the variation between snapshots ##{index} and ##{index + 1} is not what was validated between them"
      end

      snapshots.each_with_index do |(at, held, how), index|
        expect(read(at)).to eq(held), "seed #{seed}: the snapshot ##{index} at #{at.utc.iso8601(6)} (after #{how}) is not reproduced"
      end
    end
  end
end

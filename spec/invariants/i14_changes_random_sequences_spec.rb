require "rails_helper"

# B03b: after any sequence of operations - entries validated, reversed, lettered, unlettered, accounts renamed - the report of changes between two instants closes
# (I14): for every account the variation equals the movements of the lines validated between them, and the entries it lists are exactly the ones validated between them.
# Read independently of the report: by the instant of validation (`posted_at`), where the report goes by the place (`posted_seq`). The seed of a failing sequence is in the message.
RSpec.describe "Invariant I14 - the report of changes closes after random sequences" do
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
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: [ date, fiscal_year.start_date ].max, reference: "I14B-#{SecureRandom.hex(4)}", created_by_id: user.id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    made = lines.map { |attrs| create(:journal_entry_line, journal_entry: entry, **attrs) }
    entry.post!
    [ entry, made ]
  end

  def operation(rng, state)
    case rng.rand(8)
    when 0..2
      amount = BigDecimal([ 25, 60, 100, 250 ].sample(random: rng).to_s)
      entry, lines = post_entry([ { account: customer_account, partner: partners.sample(random: rng), debit: amount, credit: 0 }, { account: revenue, debit: 0, credit: amount } ])
      state[:entries] << entry
      state[:lines] << lines.first
    when 3
      amount = BigDecimal([ 10, 40, 90 ].sample(random: rng).to_s)
      state[:entries] << post_entry([ { account: expense, debit: amount, credit: 0 }, { account: revenue, debit: 0, credit: amount } ]).first
    when 4
      entry = state[:entries].map(&:reload).select(&:posted?).sample(random: rng)
      Accounting::ReverseJournalEntry.call(entry: entry, reason: "random", user: user) if entry
    when 5
      expense.update!(label_fr: "Services #{rng.rand(1000)}")
    when 6
      lettering = Accounting::Lettering.all.to_a.sample(random: rng)
      Accounting::UnletterLines.call(lettering: lettering, reason: "random", user: user) if lettering
    else
      Accounting::LetterLines.call(lines: state[:lines].map(&:reload).select { |l| l.lettering_id.nil? }.first(1), user: user) if rng.rand(3).zero? && state[:lines].any?
    end
  end

  # in SQL, by the instant of validation
  def validated_between(t1, t2)
    scope = Accounting::JournalEntryLine.joins(:journal_entry, :account)
      .where(accounting_journal_entries: { fiscal_year_id: fiscal_year.id, status: Accounting::JournalEntry.ledger_status_values })
      .where("accounting_journal_entries.posted_at > ? AND accounting_journal_entries.posted_at <= ?", t1, t2)
      .where("accounting_journal_entries.entry_date <= ?", fiscal_year.end_date)
    scope.group("accounting_accounts.code").pluck(Arel.sql("accounting_accounts.code"), Arel.sql("SUM(accounting_journal_entry_lines.debit - accounting_journal_entry_lines.credit)")).to_h.reject { |_, v| v.zero? }
  end

  def entry_ids_between(t1, t2)
    Accounting::JournalEntry.where(fiscal_year_id: fiscal_year.id, status: Accounting::JournalEntry.ledger_status_values).where("posted_at > ? AND posted_at <= ?", t1, t2).pluck(:id).sort
  end

  seeds.each do |seed|
    it "closes between every two instants of the sequence of seed #{seed}" do
      rng = Random.new(seed)
      state = { entries: [], lines: [] }
      instants = [ instant ]

      operations.times do |n|
        operation(rng, state)
        next_posting_instant
        instants << instant if n.odd?
      end

      pairs = instants.each_cons(2).to_a + [ [ instants.first, instants.last ] ]
      pairs.each_with_index do |(t1, t2), index|
        report = Changes::Report.call(fiscal_year: fiscal_year, from: t1, to: t2, show_authors: true, per: nil)
        where = "seed #{seed}, pair ##{index}"

        expect(report.closing).to be_balanced, "#{where}: the closing has a gap (#{report.closing.gaps})"
        expect(report.impact.to_h { |r| [ r.code, r.movements ] }.reject { |_, v| v.zero? }).to eq(validated_between(t1, t2)), "#{where}: the movements are not what was validated between the instants"
        expect(report.details.select { |d| %i[entries reversals].include?(d.category) }.map(&:subject_id).sort).to eq(entry_ids_between(t1, t2)), "#{where}: the entries listed are not the ones validated between the instants"
      end
    end
  end
end

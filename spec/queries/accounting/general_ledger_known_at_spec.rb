require "rails_helper"

# B03a: R02 as it was known at an instant: the lines validated by then, the running balance of those, the lettering code and the partner name that held.
RSpec.describe Accounting::GeneralLedgerQuery, "as known at an instant" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:other_account) { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let!(:alice) { create(:partner, name: "Alice") }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_line(side:, amount:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 5, reference: "G-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    line = create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: alice, side => BigDecimal(amount.to_s), other => 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account, other => BigDecimal(amount.to_s), side => 0)
    entry.post!
    next_posting_instant
    line
  end

  def ledger(known_at: nil, **options) = described_class.new(account: customer_account, fiscal_year: fiscal_year, known_at: known_at, **options).call

  let!(:invoice_line) { post_line(side: :debit, amount: 100) }
  let!(:payment_line) { post_line(side: :credit, amount: 100) }

  it "is the current ledger when the instant is now or later" do
    expect(ledger(known_at: 1.hour.from_now).map(&:to_h)).to eq(ledger.map(&:to_h))
  end

  it "leaves out the lines validated after the instant, and the balance follows" do
    after_invoice = instant
    third = post_line(side: :debit, amount: 7)

    expect(ledger(known_at: after_invoice).map(&:line_id)).to eq([ invoice_line.id, payment_line.id ])
    expect(ledger(known_at: after_invoice).last.running_balance).to eq(0)
    expect(ledger.map(&:line_id)).to include(third.id)
  end

  it "gives the lettering code that held, and filters on the lettering that held" do
    lettering = Accounting::LetterLines.call(lines: [ invoice_line, payment_line ], user: user)[:lettering]
    while_lettered = instant
    Accounting::UnletterLines.call(lettering: lettering, reason: "mistake", user: user)

    expect(ledger(known_at: while_lettered).map(&:lettering_code)).to all(eq(lettering.code))
    expect(ledger(known_at: while_lettered, lettering: :lettered).size).to eq(2)
    expect(ledger(known_at: while_lettered, lettering: :unlettered)).to be_empty
    expect(ledger.map(&:lettering_code)).to all(be_nil)
    expect(ledger(lettering: :unlettered).size).to eq(2)
  end

  it "had the lettering code of no lettering yet before it was made" do
    before_lettering = instant
    Accounting::LetterLines.call(lines: [ invoice_line, payment_line ], user: user)

    expect(ledger(known_at: before_lettering).map(&:lettering_code)).to all(be_nil)
    expect(ledger(known_at: before_lettering, lettering: :unlettered).size).to eq(2)
  end

  it "gives the partner the name it had" do
    at = instant
    alice.update!(name: "Alice Cooper")

    expect(ledger(known_at: at).map(&:partner_name).uniq).to eq([ "Alice" ])
    expect(ledger.map(&:partner_name).uniq).to eq([ "Alice Cooper" ])
  end

  it "is refused before the history" do
    expect { ledger(known_at: 3.days.ago) }.to raise_error(Accounting::KnownAt::Refused)
  end
end

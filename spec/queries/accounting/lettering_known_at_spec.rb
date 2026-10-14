require "rails_helper"

# B03a critère 4: R04 and R05 at an earlier instant show open what was lettered later, and R04 today shows it settled; a lettering that was undone since is still shown at the
# instant it held; a partial settlement is shown as it stood.
RSpec.describe "Open items as known at an instant" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:other_account) { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice") }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_line(side:, amount:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 5, reference: "L-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    line = create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: alice, side => BigDecimal(amount.to_s), other => 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account, other => BigDecimal(amount.to_s), side => 0)
    entry.post!
    next_posting_instant
    line
  end

  def aged(known_at = nil) = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: Date.current, known_at: known_at).call
  def open_lines(known_at = nil) = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: Date.current, known_at: known_at).call
  def residuals(known_at = nil) = open_lines(known_at).to_h { |r| [ r.line_id, r.residual ] }

  let!(:invoice_line) { post_line(side: :debit, amount: 100) }
  let!(:payment_line) { post_line(side: :credit, amount: 100) }

  it "is the current report when the instant is now or later" do
    expect(aged(1.hour.from_now).map(&:to_h)).to eq(aged.map(&:to_h))
    expect(open_lines(1.hour.from_now).map(&:to_h)).to eq(open_lines.map(&:to_h))
  end

  describe "a total lettering made later" do
    it "shows the lines open before it, and settled after it" do
      before_lettering = instant
      Accounting::LetterLines.call(lines: [ invoice_line, payment_line ], user: user).tap { |r| raise r.message if r.failure? }
      after_lettering = instant

      expect(residuals(before_lettering).keys).to contain_exactly(invoice_line.id, payment_line.id)
      expect(residuals(before_lettering)[invoice_line.id]).to eq(100)
      expect(residuals(after_lettering)).to be_empty
      expect(residuals).to be_empty
    end

    it "keeps showing it settled at the instants it held, once it is undone" do
      lettering = Accounting::LetterLines.call(lines: [ invoice_line, payment_line ], user: user)[:lettering]
      while_lettered = instant
      Accounting::UnletterLines.call(lettering: lettering, reason: "mistake", user: user).tap { |r| raise r.message if r.failure? }

      expect(residuals(while_lettered)).to be_empty
      expect(residuals.keys).to contain_exactly(invoice_line.id, payment_line.id)
    end
  end

  describe "a partial settlement made later" do
    let!(:small_payment) { post_line(side: :credit, amount: 40) }

    it "shows the residual as it stood at each instant" do
      before_allocation = instant
      Accounting::AllocateLines.call(lines: [ invoice_line, small_payment ]).tap { |r| raise r.message if r.failure? }
      after_allocation = instant

      expect(residuals(before_allocation)[invoice_line.id]).to eq(100)
      expect(residuals(before_allocation)[small_payment.id]).to eq(-40)
      expect(residuals(after_allocation)[invoice_line.id]).to eq(60)
      expect(residuals(after_allocation)).not_to have_key(small_payment.id)
      expect(residuals[invoice_line.id]).to eq(60)
    end

    it "shows the residual that held once the settlement is undone" do
      Accounting::AllocateLines.call(lines: [ invoice_line, small_payment ])
      while_allocated = instant
      allocation = Accounting::LineAllocation.sole
      Accounting::RemoveAllocation.call(allocation: allocation).tap { |r| raise r.message if r.failure? }

      after_removal = instant

      expect(residuals(while_allocated)[invoice_line.id]).to eq(60)
      expect(residuals(after_removal)[invoice_line.id]).to eq(100)
      expect(residuals[invoice_line.id]).to eq(100)
    end
  end

  it "shows what was posted after the instant as absent" do
    cutoff = instant
    later = post_line(side: :debit, amount: 7)

    expect(residuals(cutoff).keys).not_to include(later.id)
    expect(residuals.keys).to include(later.id)
  end

  it "is refused before the history" do
    expect { aged(3.days.ago) }.to raise_error(Accounting::KnownAt::Refused)
  end
end

require "rails_helper"

RSpec.describe Accounting::AgedBalanceQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:as_of)   { Date.current }
  let(:journal) { create(:journal, :purchase) }

  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:supplier_account) { create(:account, :supplier, reconcilable: true) }
  let!(:writedown_account) do
    create(:account, code: "400900", account_class: 4, account_type: :asset, normal_balance: :credit, reconcilable: false)
  end
  let!(:other_account) { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }

  let(:alice) { create(:partner, name: "Alice") }
  let(:bob)   { create(:partner, name: "Bob") }

  # Posts a two-line entry: `amount` on `account` (debit or credit) against 700000.
  def post_line(account:, side:, amount:, partner:, days_ago: 0, invoice: nil, post: true)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of - days_ago)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    line = create(:journal_entry_line, journal_entry: entry, account: account, partner: partner, invoice: invoice,
                  side => BigDecimal(amount.to_s), other => BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: other_account,
           other => BigDecimal(amount.to_s), side => BigDecimal("0"))
    entry.post! if post
    line
  end

  def invoice_due(days_overdue)
    create(:invoice, :posted, fiscal_year: fiscal_year, due_date: as_of - days_overdue)
  end

  def customer_rows = described_class.new(kind: :customer, as_of: as_of).call

  describe "buckets by due date" do
    {
      0  => :not_due,
      1  => :days_1_30,
      30 => :days_1_30,
      31 => :days_31_60,
      60 => :days_31_60,
      61 => :days_61_90,
      90 => :days_61_90,
      91 => :over_90
    }.each do |overdue, bucket|
      it "puts an invoice #{overdue} days overdue in #{bucket}" do
        post_line(account: customer_account, side: :debit, amount: 100, partner: alice, invoice: invoice_due(overdue))

        row = customer_rows.first
        expect(row.public_send(bucket)).to eq(BigDecimal("100"))
        expect(row.total).to eq(BigDecimal("100"))
      end
    end

    it "puts an invoice not yet due in not_due" do
      post_line(account: customer_account, side: :debit, amount: 100, partner: alice, invoice: invoice_due(-10))
      expect(customer_rows.first.not_due).to eq(BigDecimal("100"))
    end
  end

  it "falls back to the entry date when the line has no invoice" do
    post_line(account: customer_account, side: :debit, amount: 50, partner: alice, days_ago: 45)
    expect(customer_rows.first.days_31_60).to eq(BigDecimal("50"))
  end

  it "excludes lettered lines" do
    line = post_line(account: customer_account, side: :debit, amount: 100, partner: alice)
    lettering = create(:lettering, account: customer_account, partner: alice)
    line.update_columns(lettering_id: lettering.id)

    expect(customer_rows).to be_empty
  end

  it "excludes draft entries" do
    post_line(account: customer_account, side: :debit, amount: 100, partner: alice, post: false)
    expect(customer_rows).to be_empty
  end

  it "excludes lines dated after as_of" do
    post_line(account: customer_account, side: :debit, amount: 100, partner: alice, days_ago: -1)
    expect(customer_rows).to be_empty
  end

  it "excludes non-reconcilable accounts such as write-downs" do
    post_line(account: writedown_account, side: :credit, amount: 100, partner: alice)
    expect(customer_rows).to be_empty
  end

  it "puts an unallocated payment in its own column and subtracts it from the total" do
    post_line(account: customer_account, side: :debit,  amount: 100, partner: alice, invoice: invoice_due(10))
    post_line(account: customer_account, side: :credit, amount: 30,  partner: alice)

    row = customer_rows.first
    expect(row.days_1_30).to eq(BigDecimal("100"))
    expect(row.unallocated).to eq(BigDecimal("-30"))
    expect(row.total).to eq(BigDecimal("70"))
  end

  it "reverses the sign for suppliers and ignores customer accounts" do
    post_line(account: supplier_account, side: :credit, amount: 200, partner: bob, invoice: invoice_due(5))
    post_line(account: customer_account, side: :debit,  amount: 100, partner: alice)

    rows = described_class.new(kind: :supplier, as_of: as_of).call
    expect(rows.map(&:partner_name)).to eq([ "Bob" ])
    expect(rows.first.days_1_30).to eq(BigDecimal("200"))
  end

  it "groups by partner, sorted by name, with a nameless group for lines without partner" do
    post_line(account: customer_account, side: :debit, amount: 10, partner: bob)
    post_line(account: customer_account, side: :debit, amount: 20, partner: alice)
    post_line(account: customer_account, side: :debit, amount: 5,  partner: nil)

    expect(customer_rows.map(&:partner_name)).to eq([ "Alice", "Bob", nil ])
  end

  it "totals across partners" do
    post_line(account: customer_account, side: :debit, amount: 10, partner: bob)
    post_line(account: customer_account, side: :debit, amount: 20, partner: alice)

    expect(described_class.totals(customer_rows).total).to eq(BigDecimal("30"))
  end
end

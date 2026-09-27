require "rails_helper"

# R05 (docs/dev/reports/spec.md §7): lignes ouvertes (non lettrées à `as_of`) sur les
# comptes lettrables, une ligne par ligne d'écriture, plus les groupes équilibrés
# laissés sans lettrage.
RSpec.describe Accounting::UnletteredLinesQuery, type: :query, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let(:as_of)   { Date.current }
  let(:journal) { create(:journal, :purchase) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:supplier_account) { create(:account, :supplier, reconcilable: true) }
  let!(:other_account)    { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }

  let(:alice) { create(:partner, name: "Alice", payment_terms_days: 0) }
  let(:bob)   { create(:partner, name: "Bob", payment_terms_days: 0) }

  def post_line(account:, side:, amount:, partner:, days_ago: 0, invoice: nil)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of - days_ago)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    line = create(:journal_entry_line, journal_entry: entry, account: account, partner: partner, invoice: invoice,
                  side => BigDecimal(amount.to_s), other => BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: other_account,
           other => BigDecimal(amount.to_s), side => BigDecimal("0"))
    entry.post!
    line
  end

  describe "#call" do
    it "lists one row per open line, with the account, partner, dates and residual" do
      post_line(account: customer_account, side: :debit, amount: 100, partner: alice, days_ago: 10)

      row = described_class.new(kind: :customer, as_of: as_of).call.first
      expect(row.account_code).to eq(customer_account.code)
      expect(row.partner_name).to eq("Alice")
      expect(row.residual).to eq(BigDecimal("100"))
      expect(row.age_days).to eq(10)
    end

    it "excludes a fully lettered line" do
      a = post_line(account: customer_account, side: :debit, amount: 100, partner: alice)
      b = post_line(account: customer_account, side: :credit, amount: 100, partner: alice)
      lettering = create(:lettering, account: customer_account, partner: alice)
      Accounting::JournalEntryLine.where(id: [ a.id, b.id ]).update_all(lettering_id: lettering.id)

      expect(described_class.new(kind: :customer, as_of: as_of).call).to be_empty
    end

    it "shows only the residual of a partially allocated line, and drops the fully-used side entirely" do
      bill    = post_line(account: customer_account, side: :debit, amount: 100, partner: alice)
      payment = post_line(account: customer_account, side: :credit, amount: 30, partner: alice)
      Accounting::LineAllocation.create!(debit_line: bill, credit_line: payment, amount: 30, allocated_on: as_of)

      rows = described_class.new(kind: :customer, as_of: as_of).call
      expect(rows.map(&:residual)).to contain_exactly(BigDecimal("70"))
    end

    it "supports :both, listing customers and suppliers together without netting them" do
      post_line(account: customer_account, side: :debit, amount: 40, partner: alice)
      post_line(account: supplier_account, side: :credit, amount: 25, partner: bob)

      rows = described_class.new(kind: :both, as_of: as_of).call
      expect(rows.map(&:account_code)).to contain_exactly(customer_account.code, supplier_account.code)
    end

    it "matches AgedBalanceQuery's total per partner (critère d'acceptation #4)" do
      post_line(account: customer_account, side: :debit, amount: 100, partner: alice, days_ago: 10)
      post_line(account: customer_account, side: :credit, amount: 20, partner: alice, days_ago: 2)

      subtotal    = described_class.new(kind: :customer, as_of: as_of).call.select { |r| r.partner_name == "Alice" }.sum(&:residual)
      aged_total  = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: as_of).call.first.total
      expect(subtotal).to eq(aged_total)
    end
  end

  describe "#balanced_unlettered_groups" do
    it "flags a partner+account group whose open lines cancel out but were never lettered" do
      post_line(account: customer_account, side: :debit, amount: 50, partner: alice)
      post_line(account: customer_account, side: :credit, amount: 50, partner: alice)

      groups = described_class.new(kind: :customer, as_of: as_of).balanced_unlettered_groups
      expect(groups).to contain_exactly(have_attributes(partner_name: "Alice", account_code: customer_account.code))
    end

    it "does not flag a partner+account group that isn't balanced" do
      post_line(account: customer_account, side: :debit, amount: 50, partner: alice)

      expect(described_class.new(kind: :customer, as_of: as_of).balanced_unlettered_groups).to be_empty
    end
  end

  describe "isolation" do
    let(:rows_from_other_entity) do
      ActsAsTenant.with_tenant(create(:entity)) do
        other_journal  = create(:journal, :purchase)
        other_customer = create(:account, :customer, reconcilable: true)
        other_revenue  = create(:account, code: "700000", account_type: :revenue, normal_balance: :credit)
        entry = create(:journal_entry, :draft, journal: other_journal, entry_date: Date.current)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        create(:journal_entry_line, journal_entry: entry, account: other_customer, debit: 999, credit: 0)
        create(:journal_entry_line, journal_entry: entry, account: other_revenue, debit: 0, credit: 999)
        entry.post!
      end
      described_class.new(kind: :customer, as_of: as_of).call
    end

    it_behaves_like "entity scoped report"
  end
end

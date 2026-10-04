# Open customer ledger lines for the dunning specs: `open_line` posts a customer debit (or credit) that is due `days_overdue` days ago, as the
# partner has no payment terms.
RSpec.shared_context "with open customer lines" do
  include_context "with_open_fiscal_year"

  let(:as_of)   { Date.current }
  let(:journal) { create(:journal, :purchase) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:revenue)          { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice", email: "alice@example.com", payment_terms_days: 0) }
  let(:bob)   { create(:partner, name: "Bob", payment_terms_days: 0) }
  let(:policy) { Accounting::DunningPolicy.for(ActsAsTenant.current_tenant) }

  def open_line(partner: alice, amount: 100, days_overdue: 30, side: :debit, **attrs)
    ApplicationRecord.transaction do # a system spec has no wrapping transaction, and the entry is balanced only at its end
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of - days_overdue)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      other = side == :debit ? :credit : :debit
      line = create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner,
                    side => BigDecimal(amount.to_s), other => BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: revenue, other => BigDecimal(amount.to_s), side => BigDecimal("0"))
      entry.post!
      line.update_columns(attrs) if attrs.any?
      line
    end
  end
end

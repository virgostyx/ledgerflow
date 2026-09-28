require "rails_helper"

# docs/dev/reports/spec.md §7: "Sans échéance: date de pièce + conditions de
# paiement du tiers, à défaut la date de pièce."
RSpec.describe Accounting::AgedBalanceQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:as_of)   { Date.current }
  let(:journal) { create(:journal, :purchase) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:other_account)    { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }

  def post_line(partner:, days_ago:, amount: 50)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of - days_ago)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner,
           debit: BigDecimal(amount.to_s), credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account, debit: 0, credit: BigDecimal(amount.to_s))
    entry.post!
  end

  it "adds the partner's payment terms to the entry date when there is no invoice due date" do
    partner = create(:partner, payment_terms_days: 30)
    post_line(partner: partner, days_ago: 45) # entry_date + 30 days terms = 15 days overdue

    row = described_class.new(kind: :customer, as_of: as_of).call.first
    expect(row.days_1_30).to eq(BigDecimal("50"))
    expect(row.days_31_60).to eq(0)
  end

  it "falls back to the entry date alone when the partner has no payment terms" do
    partner = create(:partner, payment_terms_days: 0)
    post_line(partner: partner, days_ago: 45)

    row = described_class.new(kind: :customer, as_of: as_of).call.first
    expect(row.days_31_60).to eq(BigDecimal("50"))
  end
end

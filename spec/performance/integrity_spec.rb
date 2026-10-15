require "rails_helper"
require "benchmark"

# B03c §13 performance: the certificate of 500 000 entries in the background in under 15 minutes. Measured here on 10 000 entries written in SQL, with the rate that follows:
# the retroactive anchor (the heaviest: it fingerprints everything), the nightly check in full, the issue of the certificate, the package.
RSpec.describe "Performance - integrity" do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:journal) { create(:journal, :misc, code: "OD") }
  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let(:entries) { 10_000 }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    Ledger::SigningKeys.generate!
    conn = ApplicationRecord.connection
    conn.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    conn.execute(<<~SQL)
      INSERT INTO accounting_journal_entries (journal_id, fiscal_year_id, entry_date, reference, status, entity_id, created_at, updated_at)
      SELECT #{journal.id}, #{fiscal_year.id}, DATE '#{fiscal_year.start_date}' + (i % 300), 'PERF-' || i, 1, #{entity.id}, now(), now() FROM generate_series(1, #{entries}) AS i
    SQL
    conn.execute(<<~SQL)
      INSERT INTO accounting_journal_entry_lines (journal_entry_id, account_id, debit, credit, entity_id, entry_date, amount_residual, created_at, updated_at)
      SELECT e.id, a.account_id, a.debit, a.credit, #{entity.id}, e.entry_date, 0, now(), now()
        FROM accounting_journal_entries e CROSS JOIN (VALUES (#{customers.id}, 100, 0), (#{revenue.id}, 0, 100)) AS a(account_id, debit, credit) WHERE e.reference LIKE 'PERF-%'
    SQL
    conn.execute("ANALYZE accounting_journal_entries, accounting_journal_entry_lines")
  end

  it "anchors, checks, certifies and packages 10 000 entries at a rate that gives 500 000 in under 15 minutes" do
    timings = {}
    timings[:anchor] = Benchmark.realtime { Ledger::Anchoring.call(kind: "retroactive") }
    timings[:self_check] = Benchmark.realtime { expect(Integrity::SelfCheck.call(mode: :full)).to be_intact }
    certificate = nil
    timings[:certificate] = Benchmark.realtime { certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "full")[:certificate] }
    timings[:package] = Benchmark.realtime { Integrity::BuildPackage.call(certificate: certificate) }

    puts format("  %d entries: %s", entries, timings.map { |k, v| format("%s %.1f s", k, v) }.join(", "))
    heavy = timings[:anchor] + timings[:certificate] # what a certificate needs when nothing is fingerprinted yet: the anchor, then the issue (checks, anchors, invariants)
    expect(heavy * (500_000.0 / entries)).to be < 15 * 60
    expect(Ledger::AnchorChain.verify(entity)).to be_intact
  end
end

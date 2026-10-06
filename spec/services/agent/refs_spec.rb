require "rails_helper"

RSpec.describe Agent::Refs do
  {
    "entry:12"                              => "/accounting/journal_entries/12",
    "partner:5"                             => "/accounting/partners/5",
    "account:9"                             => "/accounting/settings/accounts/9",
    "doc:3"                                 => "/accounting/documents/3",
    "vat:4"                                 => "/accounting/vat_declarations/4",
    "audit:8"                               => "/accounting/audit_logs/8",
    "R01:2:2026-09-26"                      => "/accounting/reports/trial_balance?as_of=2026-09-26&fiscal_year_id=2",
    "R02:2:9:2026-01-01..2026-09-26"        => "/accounting/reports/general_ledger?account_id=9&date_from=2026-01-01&date_to=2026-09-26&fiscal_year_id=2",
    "R04:2026-09-26:customer:p-1042"        => "/accounting/reports/aged_balance?as_of=2026-09-26&kind=customer",
    "R05:2026-09-26:both"                   => "/accounting/reports/unlettered_lines?as_of=2026-09-26&kind=both",
    "R06:3:2026-09-26"                      => "/accounting/reports/bank_reconciliation_report?as_of=2026-09-26&bank_account_id=3",
    "R07:2"                                 => "/accounting/reports/balance_sheet?fiscal_year_id=2",
    "R08:2"                                 => "/accounting/reports/income_statement?fiscal_year_id=2",
    "R19:1"                                 => "/accounting/consistency"
  }.each do |ref, expected|
    it "opens #{ref} on #{expected.split('?').first}" do
      path = described_class.path(ref)

      expect(path.split("?").first).to eq(expected.split("?").first)
      expect(Rack::Utils.parse_query(path.split("?", 2)[1].to_s)).to eq(Rack::Utils.parse_query(expected.split("?", 2)[1].to_s))
    end
  end

  it "builds a reference from its parts" do
    expect(described_class.build("R04", "2026-09-26", "customer", "p-1")).to eq("R04:2026-09-26:customer:p-1")
  end

  it "opens nothing for a reference it does not know, a forged one, or one with nothing after its type" do
    expect(described_class.path("evil:1")).to be_nil
    expect(described_class.path("http://evil.example")).to be_nil
    expect(described_class.path("entry")).to be_nil
    expect(described_class.path(nil)).to be_nil
  end

  it "finds the references in a result, wherever they sit" do
    result = { "data" => [ { "ref" => "entry:1", "lines" => [ { "ref" => "account:2" } ] } ], "totals" => { "ref" => "R01:1:2026-01-01" }, "note" => "ref: not me" }

    expect(described_class.in_result(result)).to contain_exactly("entry:1", "account:2", "R01:1:2026-01-01")
  end
end

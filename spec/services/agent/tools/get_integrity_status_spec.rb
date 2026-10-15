require "rails_helper"

# B03c: `get_integrity_status`, to answer "is the integrity of the books verified?": the last anchor, the last check and what it found, the certificates, the keys. Nothing of the
# accounting data, and no name of a person.
RSpec.describe Agent::Tools::GetIntegrityStatus do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: Date.current) }
  let(:registry) { Agent::ToolRegistry.default }
  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 3, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
  end

  def status = registry.execute("get_integrity_status", {}, context)

  it "says that nothing was anchored or checked yet" do
    expect(status["data"].first).to include("last_anchor" => nil, "last_check" => nil, "certificates" => 0)
  end

  it "gives the last anchor, the last check and its findings, the certificates and the keys" do
    Ledger::SigningKeys.generate!
    Integrity::SelfCheck.run_for(entity)
    Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "standard")

    data = status["data"].first

    expect(data["last_anchor"]).to include("number" => 1, "entries" => 1)
    expect(data["last_check"]).to include("mode" => "nightly", "findings" => 0)
    expect(data).to include("certificates" => 1, "keys" => { "active" => 1, "retired" => 0, "revoked" => 0 }, "timestamp_authority" => false)
    expect(status.to_json).not_to include(user.email)
  end

  it "says when a check found divergences" do
    Integrity::SelfCheck.run_for(entity)
    IntegrityCheckRun.last.update_columns(findings_count: 2)

    expect(status["warnings"].join).to include("divergences")
  end

  it "is closed when the feature is off" do
    entity.update!(features: entity.features.merge("b03c" => false))

    expect(status).to include("error" => "forbidden")
  end
end

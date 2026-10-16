require "rails_helper"

# B02c, firm side of the dashboard: generate a snapshot now, let it through when the company approves first, write and approve the word of the accountant, set the alert on the forecast cash.
RSpec.describe "Portal dashboard (firm side)", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let!(:fiscal_year) { create(:fiscal_year, status: :open, entity: entity) }

  before { sign_in accountant }

  it "generates a snapshot on request and lists it with its fingerprint" do
    expect { post generate_accounting_portal_dashboard_index_path }.to change(Portal::Snapshot, :count).by(1)

    get accounting_portal_dashboard_index_path
    expect(response.body).to include(Portal::Snapshot.sole.sha256.first(12), "published")
  end

  it "lets through a snapshot that waited for the firm" do
    entity.update!(snapshot_approval_required: true)
    post generate_accounting_portal_dashboard_index_path
    snapshot = Portal::Snapshot.sole
    expect(snapshot.status).to eq("pending_review")

    post publish_accounting_portal_dashboard_path(snapshot)

    expect(snapshot.reload.status).to eq("published")
  end

  it "writes the word of the accountant and approves it, a person doing both" do
    post generate_accounting_portal_dashboard_index_path
    snapshot = Portal::Snapshot.sole

    patch word_accounting_portal_dashboard_path(snapshot), params: { text: "A good month.", source: "human" }
    expect(snapshot.reload.word_approved_at).to be_nil
    post approve_word_accounting_portal_dashboard_path(snapshot)
    expect(Portal::Snapshot.shown_word(snapshot.reload)).to eq("A good month.")
  end

  it "keeps the draft of the assistant hidden until approved, and says where it came from" do
    post generate_accounting_portal_dashboard_index_path
    snapshot = Portal::Snapshot.sole
    patch word_accounting_portal_dashboard_path(snapshot), params: { text: "Assistant draft", source: "agent_draft" }

    get accounting_portal_dashboard_index_path
    expect(response.body).to include("Assistant draft", "draft by the assistant", "Not shown to the client")
  end

  it "sets the alert on the forecast cash, and turns it off" do
    post alert_rules_accounting_portal_dashboard_index_path, params: { threshold: "5000" }
    rule = Portal::AlertRule.sole
    expect(rule).to have_attributes(kind: "cash_below", threshold: BigDecimal("5000"), active: true)

    delete alert_rule_accounting_portal_dashboard_index_path(rule: rule.id)
    expect(rule.reload.active).to be(false)
  end

  it "refuses a threshold that is not a number" do
    expect { post alert_rules_accounting_portal_dashboard_index_path, params: { threshold: "lots" } }.not_to change(Portal::AlertRule, :count)
  end

  it "lets the firm choose to approve each snapshot first" do
    patch settings_accounting_portal_dashboard_index_path, params: { snapshot_approval_required: "1" }
    expect(entity.reload.snapshot_approval_required).to be(true)
  end

  it "does not show or touch the snapshots of another company" do
    other = create(:entity)
    foreign = Portal::Snapshot.create!(entity_id: other.id, period_start: Date.current, period_end: Date.current, generated_at: Time.current, known_at: Time.current, sha256: "f" * 64)
    get accounting_portal_dashboard_index_path
    expect(response.body).not_to include("f" * 12)
    post publish_accounting_portal_dashboard_path(foreign)
    expect(response).to have_http_status(:not_found).or have_http_status(:redirect)
  end

  it "is for those who manage the portal, and closed while the feature is off" do
    sign_in reader
    expect { post generate_accounting_portal_dashboard_index_path }.not_to change(Portal::Snapshot, :count)
    sign_in accountant
    entity.update!(features: { "b02c" => false })
    get accounting_portal_dashboard_index_path
    expect(response).to redirect_to(accounting_root_path)
  end
end

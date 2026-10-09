require "rails_helper"

# B01a criterion 10: every event of the circuit is in the audit trail (R18) with who did it, the fingerprint of the content, and the channel.
RSpec.describe "Approvals: the audit trail" do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:author)      { create(:user, full_name: "Ann Author") }
  let(:owner)       { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant)  { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:invoice) do
    create(:invoice, :supplier, created_by: author, fiscal_year: fiscal_year).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "1000.00") }
  end
  let!(:policy) do
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ owner.id ], service_hours: 48, escalate_to: nil)
    end
  end

  def logs(action) = Accounting::AuditLog.for_record(invoice).for_action(action)

  def fingerprint(request) = request.content_fingerprint

  it "keeps who, what content and which channel for every event, and leaves the chain intact" do
    # submitted by the author
    request = Approvals::Submit.call(invoice: invoice, user: author)[:request]
    expect(logs("approval_submitted").sole).to have_attributes(user_id: author.id)
    expect(logs("approval_submitted").sole.payload).to include("content_fingerprint" => fingerprint(request), "request_id" => request.id)

    # handed over by the owner, from the web
    Approvals::Decide.call(request: request, user: owner, decision: :transferred, transfer_to_id: accountant.id, content_fingerprint: fingerprint(request), channel: :web)
    transferred = logs("approval_transferred").sole
    expect(transferred).to have_attributes(user_id: owner.id)
    expect(transferred.payload).to include("channel" => "web", "content_fingerprint" => fingerprint(request), "transferred_to" => accountant.id, "step" => 1)

    # the content changes: the approval is invalidated, and the circuit starts again
    invoice.lines.first.update!(unit_price: "2000.00")
    expect(logs("approval_invalidated").sole.payload).to include("request_id" => request.id, "was" => fingerprint(request), "now" => Approvals::ContentFingerprint.call(invoice))
    expect(logs("approval_submitted").count).to eq(2)
    fresh = Approvals::Request.pending.sole

    # time goes by: a reminder, then the escalation (to the owners, nobody being named)
    travel 49.hours do
      Approvals::ProcessDue.call
    end
    expect(logs("approval_reminder").sole.payload).to include("request_id" => fresh.id, "number" => 2, "step" => 1) # one a run, even when two delays went by
    expect(logs("approval_escalated").sole.payload).to include("request_id" => fresh.id, "escalated_to" => "owners", "step" => 1)

    # refused by the owner from the phone, with a reason
    Approvals::Decide.call(request: fresh, user: owner, decision: :rejected, comment: "Wrong price", content_fingerprint: fingerprint(fresh), channel: :mobile, device_fingerprint: "ua-1")
    rejected = logs("approval_rejected").sole
    expect(rejected).to have_attributes(user_id: owner.id, reason: "Wrong price")
    expect(rejected.payload).to include("channel" => "mobile", "content_fingerprint" => fingerprint(fresh), "device_fingerprint" => "ua-1", "step" => 1)

    expect(Accounting::AuditVerifier.call(entity: entity)).to be_intact
  end

  it "keeps an approval from the api channel, and one in the name of someone else" do
    request = Approvals::Submit.call(invoice: invoice, user: author)[:request]
    Approvals::Decide.call(request: request, user: owner, decision: :transferred, transfer_to_id: accountant.id, content_fingerprint: fingerprint(request))

    Approvals::Decide.call(request: request, user: accountant, decision: :approved, content_fingerprint: fingerprint(request), channel: :api, device_fingerprint: "token-7")

    approved = logs("approval_approved").sole
    expect(approved).to have_attributes(user_id: accountant.id)
    expect(approved.payload).to include("channel" => "api", "on_behalf_of" => owner.id, "content_fingerprint" => fingerprint(request), "device_fingerprint" => "token-7")
  end

  it "keeps a request that needs no approval, and a rerouting" do
    Approvals::Policy.update_all(active: false)
    Approvals::Submit.call(invoice: invoice, user: author)
    expect(logs("approval_not_required").sole).to have_attributes(user_id: author.id)

    policy.update_columns(active: true) # update_all above left the object as it was: say it to the database
    create(:user_entity, :admin, user: create(:user), entity: entity) # an owner who stays
    UserEntity.find_by(user: owner, entity: entity).update!(active: false)
    other = create(:invoice, :supplier, fiscal_year: fiscal_year).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "50.00") }
    request = Approvals::Submit.call(invoice: other, user: nil)[:request]

    Approvals::ProcessDue.call

    log = Accounting::AuditLog.for_record(other).for_action("approval_rerouted").sole
    expect(log.payload).to include("request_id" => request.id, "step" => 1)
  end

  it "keeps who wrote and who ended a delegation, and every change of a policy" do
    Current.user = owner
    delegation = Approvals::Delegation.create!(delegator: owner, delegate: accountant, starts_on: Date.current, ends_on: Date.current + 3, reason: "leave")
    delegation.destroy!
    policy.update!(name: "Renamed")

    expect(Accounting::AuditLog.for_record(delegation).chronologic.map { |l| [ l.action, l.user_id ] }).to eq([ [ "create", owner.id ], [ "destroy", owner.id ] ])
    update = Accounting::AuditLog.for_record(policy).for_action("update").last
    expect(update).to have_attributes(user_id: owner.id)
    expect(update.payload["changes"]["name"]).to eq([ "p", "Renamed" ])
  ensure
    Current.reset
  end
end

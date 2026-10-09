require "rails_helper"

# B01a §4 "Délais, escalade et absence": reminders at 24 and 48 hours, escalation when the service time is over,
# rerouting when nobody named can decide any more.
RSpec.describe Approvals::ProcessDue do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:author)      { create(:user) }
  let(:owner)       { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:boss)        { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let!(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:invoice) do
    create(:invoice, :supplier, created_by: author, fiscal_year: fiscal_year).tap do |i|
      create(:invoice_line, invoice: i, account: create(:account), unit_price: "1000.00")
    end
  end
  let(:escalate_to) { boss }
  let!(:policy) do
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ accountant.id ], service_hours: 72, escalate_to: escalate_to)
      p.steps.create!(position: 2, mode: :any_of, approver_roles: %w[admin], service_hours: 24)
    end
  end

  def notifications(event_prefix, user = nil)
    scope = Accounting::Notification.where("event LIKE ?", "#{event_prefix}%")
    user ? scope.where(user: user) : scope
  end

  def audit(action) = Accounting::AuditLog.for_record(invoice).for_action(action)

  around { |example| travel_to(Time.zone.local(2026, 10, 12, 9, 0)) { example.run } }

  let!(:request) { Approvals::Submit.call(invoice: invoice, user: author)[:request] }

  def later(hours) = travel(hours.hours)

  it "says nothing before the first delay" do
    later 23
    described_class.call

    expect(Accounting::Notification.count).to eq(0)
  end

  describe "reminders" do
    it "reminds the approvers of the level after 24 hours, and again after 48, no more" do
      later 24
      described_class.call
      expect(notifications("approval_reminder", accountant).count).to eq(1)
      expect(notifications("approval_reminder", owner)).to be_empty # not an approver of this level

      later 1
      described_class.call
      expect(notifications("approval_reminder").count).to eq(1)

      later 23
      described_class.call
      expect(notifications("approval_reminder", accountant).count).to eq(2)

      later 1
      described_class.call
      expect(notifications("approval_reminder").count).to eq(2)
      expect(audit("approval_reminder").count).to eq(2)
    end

    it "follows the hours of the policy" do
      policy.update!(reminder_hours: [ 4 ])
      later 5
      described_class.call

      expect(notifications("approval_reminder", accountant).count).to eq(1)
    end

    it "sends one reminder when several delays went by unnoticed, not a burst" do
      later 60
      described_class.call

      expect(notifications("approval_reminder", accountant).count).to eq(1)
      later 1
      described_class.call
      expect(notifications("approval_reminder", accountant).count).to eq(1)
    end

    it "does not remind a request that is decided" do
      approver = accountant
      Approvals::Decide.call(request: request, user: approver, decision: :approved, content_fingerprint: request.content_fingerprint)
      request.reload.update!(status: :rejected) # closed whatever the way
      later 30
      described_class.call

      expect(Accounting::Notification.count).to eq(0)
    end
  end

  describe "escalation" do
    it "calls in the person named when the service time is over, once, and that person may then decide" do
      later 73
      described_class.call

      expect(request.reload.escalated_to_id).to eq(boss.id)
      expect(request.escalated_at).to be_present
      expect(notifications("approval_escalated", boss).count).to eq(1)
      expect(audit("approval_escalated").count).to eq(1)
      expect(Approvals::Approvers.for(request)).to include(boss.id => nil, accountant.id => nil)

      later 5
      described_class.call
      expect(notifications("approval_escalated").count).to eq(1)

      expect(Approvals::Decide.call(request: request, user: boss, decision: :approved, content_fingerprint: request.content_fingerprint)).to be_success
    end

    it "calls in the owners when nobody is named to escalate to" do
      policy.steps.find_by(position: 1).update!(escalate_to: nil)
      owner
      later 73
      described_class.call

      expect(notifications("approval_escalated", owner).count).to eq(1)
      expect(Approvals::Approvers.for(request.reload)).to include(owner.id)
    end

    it "calls in the owners when the person named could not approve anyway" do
      lowly = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }
      policy.steps.find_by(position: 1).update!(escalate_to: lowly)
      owner
      later 73
      described_class.call

      expect(notifications("approval_escalated", lowly)).to be_empty
      expect(notifications("approval_escalated", owner).count).to eq(1)
    end

    it "starts again with the clock of the next level" do
      Approvals::Decide.call(request: request, user: accountant, decision: :approved, content_fingerprint: request.content_fingerprint)
      request.reload
      expect(request).to have_attributes(current_step: 2, reminders_sent: 0, escalated_at: nil)
      owner
      later 25
      described_class.call

      expect(notifications("approval_reminder", owner).count).to eq(1)
      expect(notifications("approval_escalated", owner).count).to eq(1) # level 2 has a service time of 24 hours, no one named: the owners
    end
  end

  describe "rerouting" do
    it "sends the request to the owners, with an alert, when nobody named can decide any more" do
      UserEntity.find_by(user: accountant, entity: entity).update!(active: false)
      owner
      described_class.call

      expect(request.reload.rerouted_at).to be_present
      expect(notifications("approval_rerouted", owner).count).to eq(1)
      expect(audit("approval_rerouted").count).to eq(1)
      expect(Approvals::Approvers.for(request)).to include(owner.id)
      expect(Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint)).to be_success
    end

    it "does it once" do
      UserEntity.find_by(user: accountant, entity: entity).update!(active: false)
      owner
      described_class.call
      described_class.call

      expect(notifications("approval_rerouted").count).to eq(1)
    end

    it "does nothing while someone can still decide" do
      owner
      described_class.call

      expect(request.reload.rerouted_at).to be_nil
    end
  end

  it "ignores an entity that has the feature off, and works through all the others" do
    other = create(:entity)
    entity.update!(features: entity.features.merge("b01a" => false))
    later 25
    described_class.call

    expect(Accounting::Notification.count).to eq(0)
    expect(other).to be_persisted
  end
end

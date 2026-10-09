require "rails_helper"

# B01a: the data of the approval circuit (docs/dev/signature/spec.md §4).
RSpec.describe "Approvals models" do
  include_context "with entity"

  let(:user) { create(:user) }

  describe Approvals::Policy do
    it "is for purchase invoices or payment batches, active by default, at version 1" do
      policy = described_class.create!(name: "Small invoices", subject: :purchase_invoice, priority: 10)

      expect(policy).to be_purchase_invoice
      expect(policy.active).to be true
      expect(policy.version).to eq(1)
      expect(policy.conditions).to eq({})
    end

    it "needs a name and a subject" do
      expect(described_class.new(subject: :purchase_invoice)).not_to be_valid
      expect(described_class.new(name: "x")).not_to be_valid
    end

    it "is written to the audit trail" do
      policy = described_class.create!(name: "Audited", subject: :purchase_invoice, priority: 5)

      expect(Accounting::AuditLog.for_record(policy).for_action("create")).to exist
    end

    it "keeps its steps in order" do
      policy = described_class.create!(name: "Two levels", subject: :purchase_invoice, priority: 1)
      policy.steps.create!(position: 2, mode: :all_of, approver_roles: %w[admin])
      policy.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ user.id ])

      expect(policy.steps.map(&:position)).to eq([ 1, 2 ])
    end
  end

  describe Approvals::Step do
    let(:policy) { Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1) }

    it "needs at least one approver, by person or by role" do
      expect(policy.steps.build(position: 1, mode: :any_of)).not_to be_valid
      expect(policy.steps.build(position: 1, mode: :any_of, approver_roles: %w[accountant])).to be_valid
    end

    it "refuses a role that cannot approve" do
      expect(policy.steps.build(position: 1, mode: :any_of, approver_roles: %w[assistant])).not_to be_valid
    end

    it "has one position per policy" do
      policy.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])

      expect(policy.steps.build(position: 1, mode: :any_of, approver_roles: %w[admin])).not_to be_valid
    end
  end

  describe Approvals::Request do
    let(:invoice) { create(:invoice, :supplier) }

    it "starts pending, at the first step, on the content it was given" do
      request = described_class.create!(subject: invoice, content_fingerprint: "a" * 64, submitted_by: user)

      expect(request).to be_pending
      expect(request.current_step).to eq(1)
    end

    it "lets only one request be open on a subject" do
      described_class.create!(subject: invoice, content_fingerprint: "a" * 64, submitted_by: user)

      expect(described_class.new(subject: invoice, content_fingerprint: "b" * 64, submitted_by: user)).not_to be_valid
    end

    it "lets a new one open once the earlier one is closed" do
      described_class.create!(subject: invoice, content_fingerprint: "a" * 64, submitted_by: user, status: :invalidated)

      expect(described_class.new(subject: invoice, content_fingerprint: "b" * 64, submitted_by: user)).to be_valid
    end
  end

  describe Approvals::Delegation do
    let(:other) { create(:user) }

    before do
      create(:user_entity, :accountant, user: user, entity: entity)
      create(:user_entity, :accountant, user: other, entity: entity)
    end

    it "is between two people who can approve in this entity" do
      outsider = create(:user)
      assistant = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }

      expect(described_class.new(delegator: user, delegate: outsider, starts_on: Date.current, ends_on: Date.current + 1, reason: "x")).not_to be_valid
      expect(described_class.new(delegator: user, delegate: assistant, starts_on: Date.current, ends_on: Date.current + 1, reason: "x")).not_to be_valid
      expect(described_class.new(delegator: outsider, delegate: user, starts_on: Date.current, ends_on: Date.current + 1, reason: "x")).not_to be_valid
    end

    it "is written to the audit trail" do
      delegation = described_class.create!(delegator: user, delegate: other, starts_on: Date.current, ends_on: Date.current + 3, reason: "leave")

      expect(Accounting::AuditLog.for_record(delegation).for_action("create")).to exist
    end

    it "is limited in time and ends after it starts" do
      expect(described_class.new(delegator: user, delegate: other, starts_on: Date.current, ends_on: Date.current - 1, reason: "leave")).not_to be_valid
      expect(described_class.new(delegator: user, delegate: other, starts_on: Date.current, ends_on: Date.current + 7, reason: "leave")).to be_valid
    end

    it "needs a reason and cannot be to oneself" do
      expect(described_class.new(delegator: user, delegate: other, starts_on: Date.current, ends_on: Date.current + 1)).not_to be_valid
      expect(described_class.new(delegator: user, delegate: user, starts_on: Date.current, ends_on: Date.current + 1, reason: "x")).not_to be_valid
    end

    it "covers a day only between its dates, first and last included" do
      delegation = described_class.create!(delegator: user, delegate: other, starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 12), reason: "leave")

      expect(described_class.in_force_on(Date.new(2026, 10, 9))).to be_empty
      expect(described_class.in_force_on(Date.new(2026, 10, 10))).to contain_exactly(delegation)
      expect(described_class.in_force_on(Date.new(2026, 10, 12))).to contain_exactly(delegation)
      expect(described_class.in_force_on(Date.new(2026, 10, 13))).to be_empty
    end
  end

  describe Approvals::Decision do
    it "is kept on the request, with the content the person saw" do
      request = Approvals::Request.create!(subject: create(:invoice, :supplier), content_fingerprint: "a" * 64, submitted_by: user)
      decision = request.decisions.create!(step_position: 1, approver: user, decision: :approved, content_fingerprint: "a" * 64, channel: :web)

      expect(decision).to be_approved
      expect(decision.decided_at).to be_present
    end
  end

  describe "the payment status of an invoice" do
    it "is not required by default, so nothing existing changes" do
      expect(create(:invoice, :supplier).payment_status).to eq("not_required")
    end
  end
end

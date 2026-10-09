require "rails_helper"

# B01a §4: approve, refuse, ask for changes; separation of tasks, delegations, and the content the approver saw.
RSpec.describe Approvals::Decide do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:author)      { create(:user) }
  let(:owner)       { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant)  { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)   { create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:invoice) do
    create(:invoice, :supplier, created_by: author, fiscal_year: fiscal_year).tap do |i|
      create(:invoice_line, invoice: i, account: create(:account), unit_price: "1000.00")
    end
  end

  def policy!(*steps)
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1).tap do |policy|
      steps.each_with_index { |attrs, index| policy.steps.create!({ position: index + 1, mode: :any_of }.merge(attrs)) }
    end
  end

  def submit! = Approvals::Submit.call(invoice: invoice, user: author)[:request]

  def decide(request, user, decision = :approved, **extra)
    described_class.call(request: request, user: user, decision: decision, content_fingerprint: request.content_fingerprint, **extra)
  end

  def audit(action) = Accounting::AuditLog.for_record(invoice).for_action(action)

  describe "approving" do
    before { policy!({ approver_roles: %w[admin] }) }

    it "approves the invoice, keeps the decision with what the approver saw, and makes it payable" do
      request = submit!
      result = decide(request, owner, channel: :mobile, device_fingerprint: "ua-1")

      expect(result).to be_success
      expect(request.reload).to be_approved
      expect(request.decided_at).to be_present
      expect(invoice.reload).to be_payment_approved
      decision = request.decisions.sole
      expect(decision).to have_attributes(approver: owner, step_position: 1, channel: "mobile", device_fingerprint: "ua-1", content_fingerprint: request.content_fingerprint)
      expect(audit("approval_approved").count).to eq(1)
      expect(audit("approval_approved").last.payload).to include("channel" => "mobile", "content_fingerprint" => request.content_fingerprint)
    end

    it "refuses someone the policy does not name" do
      request = submit!

      expect(decide(request, accountant)).to be_failure
      expect(request.reload).to be_pending
      expect(request.decisions).to be_empty
    end

    it "refuses someone who cannot approve at all, even when named" do
      policy = Approvals::Policy.first
      policy.steps.first.update!(approver_user_ids: [ assistant.id ])
      request = submit!

      expect(decide(request, assistant)).to be_failure
    end

    it "refuses the author of the invoice, who may not approve their own entry" do
      author_owner = create(:user_entity, :admin, user: author, entity: entity).user
      request = submit!

      result = decide(request, author_owner)

      expect(result).to be_failure
      expect(request.reload).to be_pending
    end

    it "lets the author approve when the entity allows self-approval" do
      author_owner = create(:user_entity, :admin, user: author, entity: entity).user
      entity.update!(allow_self_approval: true)
      request = submit!

      expect(decide(request, author_owner)).to be_success
    end

    it "does not block anyone on an invoice nobody typed (Peppol, recurring)" do
      invoice.update_columns(created_by_id: nil)
      request = submit!

      expect(decide(request, owner)).to be_success
    end

    it "refuses a content the approver did not have in front of them" do
      request = submit!

      result = described_class.call(request: request, user: owner, decision: :approved, content_fingerprint: "0" * 64)

      expect(result).to be_failure
      expect(result.message).to match(/changed/i)
      expect(request.reload).to be_pending
    end

    it "refuses a request that is no longer pending" do
      request = submit!
      decide(request, owner)

      expect(decide(request, owner)).to be_failure
    end

    it "is refused when the entity has not got the feature on" do
      request = submit!
      entity.update!(features: entity.features.merge("b01a" => false))

      expect(decide(request, owner)).to be_failure
    end
  end

  describe "refusing and asking for changes" do
    before { policy!({ approver_roles: %w[admin] }) }

    it "needs a reason to refuse, and stops the circuit holding the payment" do
      request = submit!

      expect(decide(request, owner, :rejected)).to be_failure
      expect(decide(request, owner, :rejected, comment: "Not what we ordered")).to be_success
      expect(request.reload).to be_rejected
      expect(invoice.reload).to be_payment_on_hold
      expect(audit("approval_rejected").count).to eq(1)
    end

    it "asks the author for changes with a task, and closes the request" do
      author_member = create(:user_entity, :assistant, user: author, entity: entity)
      request = submit!

      expect(decide(request, owner, :changes_requested)).to be_failure
      result = decide(request, owner, :changes_requested, comment: "Please add the PO number")

      expect(result).to be_success
      expect(request.reload).to be_changes_requested
      task = Accounting::Task.about(invoice).sole
      expect(task).to have_attributes(assignee: author_member.user, title: a_string_including("Changes requested"), description: "Please add the PO number")
      expect(invoice.reload).to be_payment_on_hold
    end
  end

  describe "levels" do
    it "moves to the next level once one of a level's approvers has approved" do
      policy!({ approver_roles: %w[accountant] }, { approver_roles: %w[admin] })
      request = submit!

      decide(request, accountant)
      expect(request.reload).to be_pending
      expect(request.current_step).to eq(2)
      expect(invoice.reload).to be_payment_to_approve
      expect(decide(request, accountant)).to be_failure # not named at level 2

      expect(decide(request, owner)).to be_success
      expect(request.reload).to be_approved
    end

    it "needs every named person when the level is all_of, and one per named role" do
      second = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }
      policy!({ mode: :all_of, approver_user_ids: [ accountant.id, second.id ], approver_roles: %w[admin] })
      request = submit!

      decide(request, accountant)
      decide(request, second)
      expect(request.reload).to be_pending

      decide(request, owner)
      expect(request.reload).to be_approved
    end

    it "does not let the same person decide twice on a level" do
      second = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }
      policy!({ mode: :all_of, approver_user_ids: [ accountant.id, second.id ] })
      request = submit!
      decide(request, accountant)

      expect(decide(request, accountant)).to be_failure
      expect(request.reload).to be_pending
    end

    it "stops at the first refusal, whatever the level" do
      policy!({ approver_roles: %w[accountant] }, { approver_roles: %w[admin] })
      request = submit!
      decide(request, accountant)

      decide(request, owner, :rejected, comment: "No")

      expect(request.reload).to be_rejected
    end
  end

  describe "delegations" do
    before { policy!({ approver_user_ids: [ owner.id ] }) }

    let(:delegate) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

    def delegate!(from: owner, to: delegate, starts: Date.current - 1, ends: Date.current + 1, policy_ids: [])
      Approvals::Delegation.create!(delegator: from, delegate: to, starts_on: starts, ends_on: ends, reason: "away", policy_ids: policy_ids)
    end

    it "lets the delegate decide in the name of the delegator, and keeps both names" do
      delegate!
      request = submit!

      expect(decide(request, delegate)).to be_success
      expect(request.decisions.sole).to have_attributes(approver: delegate, on_behalf_of: owner)
    end

    it "stops on the day after it ends" do
      delegate!(ends: Date.current - 1)
      request = submit!

      expect(decide(request, delegate)).to be_failure
    end

    it "is not transitive" do
      third = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }
      delegate!
      delegate!(from: delegate, to: third)
      request = submit!

      expect(decide(request, third)).to be_failure
    end

    it "does not let a delegate approve what the delegator typed" do
      invoice.update_columns(created_by_id: owner.id)
      delegate!
      request = submit!

      expect(decide(request, delegate)).to be_failure
    end

    it "does not let a delegate approve their own entry" do
      invoice.update_columns(created_by_id: delegate.id)
      delegate!
      request = submit!

      expect(decide(request, delegate)).to be_failure
    end

    it "is limited to the policies it names" do
      delegate!(policy_ids: [ 0 ])
      request = submit!

      expect(decide(request, delegate)).to be_failure
    end

    it "is refused when the delegate cannot approve at all" do
      lowly = assistant
      delegate!(to: lowly)
      request = submit!

      expect(decide(request, lowly)).to be_failure
    end
  end
end

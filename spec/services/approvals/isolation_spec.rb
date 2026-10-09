require "rails_helper"

# B01a: the approval circuit never looks outside the entity it works in. Two companies share one database and some people (an accountant who
# works for both): a right held in company B counts for nothing in company A.
RSpec.describe "Approvals: isolation between entities" do
  let(:company_a) { create(:entity) }
  let(:company_b) { create(:entity) }

  let(:owner_a)      { create(:user, email: "owner-a@firm.test") }
  let(:owner_b)      { create(:user, email: "owner-b@firm.test") }
  let(:accountant_a) { create(:user, email: "acc-a@firm.test") }
  let(:both)         { create(:user, email: "both@firm.test") } # an accountant in B only

  before do
    create(:user_entity, :admin, user: owner_a, entity: company_a)
    create(:user_entity, :accountant, user: accountant_a, entity: company_a)
    create(:user_entity, :admin, user: owner_b, entity: company_b)
    create(:user_entity, :accountant, user: both, entity: company_b)
    ActionMailer::Base.deliveries.clear
  end

  def in_a(&block) = ActsAsTenant.with_tenant(company_a, &block)

  # notifications belong to an entity: read across all of them, to see where they went
  def told(*users) = ActsAsTenant.without_tenant { Accounting::Notification.where(user: users).pluck(:event) }

  def pending_request_in_a(steps: [ { approver_roles: %w[admin accountant] } ])
    in_a do
      fiscal_year = create(:fiscal_year, status: :open)
      policy = Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1)
      steps.each_with_index { |attrs, i| policy.steps.create!({ position: i + 1, mode: :any_of }.merge(attrs)) }
      invoice = create(:invoice, :supplier, fiscal_year: fiscal_year).tap { |inv| create(:invoice_line, invoice: inv, account: create(:account), unit_price: "100.00") }
      Approvals::Submit.call(invoice: invoice, user: nil)[:request]
    end
  end

  it "does not take the owner of another company for an approver, by role" do
    request = pending_request_in_a

    in_a do
      expect(Approvals::Approvers.for(request).keys).to contain_exactly(owner_a.id, accountant_a.id)
      expect(Approvals::Decide.call(request: request, user: owner_b, decision: :approved, content_fingerprint: request.content_fingerprint)).to be_failure
    end
  end

  it "does not let someone who is an approver elsewhere decide here, even when named" do
    request = pending_request_in_a(steps: [ { approver_user_ids: [ both.id ] } ])

    in_a do
      expect(Approvals::Approvers.for(request)).to be_empty
      expect(Approvals::Decide.call(request: request, user: both, decision: :approved, content_fingerprint: request.content_fingerprint)).to be_failure
    end
  end

  it "calls in only the owners of its own entity when a request is rerouted or escalated" do
    request = pending_request_in_a(steps: [ { approver_user_ids: [ both.id ], service_hours: 1 } ]) # nobody of A can decide: rerouted at once
    travel 2.hours

    Approvals::ProcessDue.call

    expect(told(owner_a).join).to include("approval_rerouted", "approval_escalated")
    expect(told(owner_b, both)).to be_empty
    in_a { expect(Approvals::Approvers.for(request.reload).keys).to eq([ owner_a.id ]) }
  end

  it "does not escalate to a person who is not of the entity" do
    request = pending_request_in_a(steps: [ { approver_roles: %w[accountant], service_hours: 1, escalate_to_id: owner_b.id } ])
    travel 2.hours

    Approvals::ProcessDue.call

    expect(told(owner_b)).to be_empty
    expect(request.reload.escalated_to_id).to be_nil
    expect(told(owner_a).join).to include("approval_escalated")
  end

  it "mails the summary only to the approvers of the entity the requests are in" do
    pending_request_in_a

    Approvals::DigestJob.perform_now

    expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly("owner-a@firm.test", "acc-a@firm.test")
  end

  it "makes a delegation only between people who can approve in this entity" do
    in_a do
      delegation = Approvals::Delegation.new(delegator: owner_a, delegate: both, starts_on: Date.current, ends_on: Date.current + 3, reason: "leave")

      expect(delegation).not_to be_valid
      expect(delegation.errors[:delegate]).to be_present
    end
  end

  it "gives a task to nobody of another company when it asks for changes" do
    request = pending_request_in_a
    in_a { request.subject.update_columns(created_by_id: both.id) } # the author works for B only

    in_a do
      result = Approvals::Decide.call(request: request, user: owner_a, decision: :changes_requested, comment: "Fix it", content_fingerprint: request.content_fingerprint)

      expect(result).to be_success
      expect(Accounting::Task.about(request.subject).sole.assignee).to be_nil
    end
  end
end

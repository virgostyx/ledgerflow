require "rails_helper"

# B01a: writing an approval policy. One that requests were made under is never edited under their feet: it is retired
# and a new version takes its place.
RSpec.describe Approvals::SavePolicy do
  include_context "with entity"

  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:steps) { [ { mode: "any_of", approver_roles: %w[accountant], service_hours: "48" }, { mode: "all_of", approver_user_ids: [ owner.id ] } ] }
  let(:attributes) { { name: "Over 1,000", priority: 10, conditions: { min_amount: "1000" }, reminder_hours: [ 24, 48 ] } }

  def save(policy: nil, attrs: attributes, steps: self.steps) = described_class.call(policy: policy, attributes: attrs, steps: steps)

  describe "a new policy" do
    it "is saved with its levels numbered in the order given" do
      result = save

      expect(result).to be_success
      policy = result[:policy]
      expect(policy).to have_attributes(name: "Over 1,000", priority: 10, version: 1, active: true, conditions: { "min_amount" => "1000" })
      expect(policy.steps.map { |s| [ s.position, s.mode, s.approver_roles, s.approver_user_ids, s.service_hours ] }).to eq(
        [ [ 1, "any_of", %w[accountant], [], 48 ], [ 2, "all_of", [], [ owner.id ], nil ] ]
      )
    end

    it "needs at least one level" do
      result = save(steps: [])

      expect(result).to be_failure
      expect(result.message).to match(/at least one level/i)
      expect(Approvals::Policy.count).to eq(0)
    end

    it "needs an approver at every level, and saves nothing otherwise" do
      result = save(steps: [ { mode: "any_of", approver_roles: %w[accountant] }, { mode: "any_of", service_hours: "24" } ])

      expect(result).to be_failure
      expect(result.message).to match(/level 2/i)
      expect(Approvals::Policy.count).to eq(0)
    end

    it "needs a name" do
      expect(save(attrs: attributes.merge(name: ""))).to be_failure
    end

    it "ignores a level left entirely blank, as a form sends one to add another" do
      expect(save(steps: steps + [ { mode: "any_of", approver_user_ids: [ "" ], approver_roles: [ "" ] } ])[:policy].steps.size).to eq(2)
    end
  end

  describe "the conditions" do
    it "keep what is filled in, typed, and nothing else" do
      conditions = { min_amount: "1000", max_amount: "", partner_ids: [ "", "4", "7" ], account_ids: [], project_ids: "3, 9", currencies: "usd, gbp",
                     document_types: [ "", "credit_note", "bogus" ], first_payment: "1", unknown: "x" }

      expect(save(attrs: attributes.merge(conditions: conditions))[:policy].conditions).to eq(
        "min_amount" => "1000", "partner_ids" => [ 4, 7 ], "project_ids" => [ 3, 9 ], "currencies" => %w[USD GBP], "document_types" => %w[credit_note], "first_payment" => true
      )
    end

    it "refuse an amount that is not a number" do
      expect(save(attrs: attributes.merge(conditions: { min_amount: "lots" }))).to be_failure
    end
  end

  describe "an existing policy nobody has been asked under" do
    let!(:policy) { save[:policy] }

    it "is edited in place, its levels replaced, its version kept" do
      result = save(policy: policy, attrs: attributes.merge(name: "Renamed"), steps: [ { mode: "any_of", approver_roles: %w[admin] } ])

      expect(result[:policy]).to eq(policy)
      expect(policy.reload).to have_attributes(name: "Renamed", version: 1, active: true)
      expect(policy.steps.map(&:approver_roles)).to eq([ %w[admin] ])
    end
  end

  describe "a policy requests were made under" do
    let(:invoice) do
      create(:invoice, :supplier, fiscal_year: create(:fiscal_year, status: :open)).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "2000.00") }
    end
    let!(:policy) { save[:policy] }
    let!(:request) { Approvals::Submit.call(invoice: invoice, user: nil)[:request] }

    it "is retired and replaced by a new version, so the request keeps its levels" do
      result = save(policy: policy, attrs: attributes.merge(name: "Over 1,000 (new)"), steps: [ { mode: "any_of", approver_roles: %w[admin] } ])

      successor = result[:policy]
      expect(successor).not_to eq(policy)
      expect(successor).to have_attributes(name: "Over 1,000 (new)", version: 2, active: true)
      expect(policy.reload).to have_attributes(active: false, version: 1)
      expect(policy.steps.map(&:approver_roles)).to eq([ %w[accountant], [] ])
      expect(request.reload).to have_attributes(policy: policy, policy_version: 1)
    end

    it "is the successor that serves the next invoice" do
      successor = save(policy: policy, steps: [ { mode: "any_of", approver_roles: %w[admin] } ])[:policy]
      other = create(:invoice, :supplier, fiscal_year: invoice.fiscal_year).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "3000.00") }

      expect(Approvals::PolicyMatcher.call(other)).to eq(successor)
    end

    it "is edited in place when only its name, priority, conditions or timing change: the levels are what requests depend on" do
      result = save(policy: policy, attrs: attributes.merge(name: "Renamed", priority: 3))

      expect(result[:policy]).to eq(policy)
      expect(policy.reload).to have_attributes(name: "Renamed", priority: 3, version: 1)
      expect(Approvals::Policy.count).to eq(1)
    end

    it "is recorded in the audit trail as revised" do
      successor = save(policy: policy, steps: [ { mode: "any_of", approver_roles: %w[admin] } ])[:policy]

      log = Accounting::AuditLog.for_record(successor).for_action("approval_policy_revised").sole
      expect(log.payload).to include("replaces" => policy.id, "version" => 2)
    end

    it "is retired without a successor when it is switched off" do
      result = save(policy: policy, attrs: attributes.merge(active: false))

      expect(result[:policy].reload).to have_attributes(active: false)
      expect(Approvals::PolicyMatcher.call(invoice)).to be_nil
    end
  end
end

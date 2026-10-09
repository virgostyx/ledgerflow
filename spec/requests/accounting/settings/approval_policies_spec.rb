require "rails_helper"

# B01a, the owner's side: the approval policies and the delegations.
RSpec.describe "Approval policies and delegations (B01a)", type: :request do
  include_context "with entity"

  let(:owner)      { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)  { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }

  let(:valid_params) do
    { policy: { name: "Over 1,000", priority: "10", active: "1", reminder_hours: "24, 48", conditions: { min_amount: "1000", currencies: "eur" } },
      steps: { "0" => { mode: "any_of", approver_roles: [ "", "accountant" ], approver_user_ids: [ "" ], service_hours: "48", escalate_to_id: owner.id.to_s },
               "1" => { mode: "all_of", approver_roles: [ "" ], approver_user_ids: [ "", owner.id.to_s ], service_hours: "", escalate_to_id: "" },
               "2" => { mode: "any_of", approver_roles: [ "" ], approver_user_ids: [ "" ], service_hours: "", escalate_to_id: "" } } }
  end

  before { sign_in owner }

  describe "the right" do
    it "is closed when the feature is off" do
      entity.update!(features: entity.features.merge("b01a" => false))

      get accounting_settings_approval_policies_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "is the owner's: an accountant is turned away" do
      sign_in accountant

      get accounting_settings_approval_policies_path
      expect(response).to redirect_to(root_path).or redirect_to(accounting_root_path)
      post accounting_settings_approval_policies_path, params: valid_params
      expect(Approvals::Policy.count).to eq(0)
    end

    it "is linked from the settings, for the owner" do
      get accounting_settings_root_path

      expect(response.body).to include("Invoice approval")
    end
  end

  describe "the policies" do
    it "say so when there is none yet" do
      get accounting_settings_approval_policies_path

      expect(response.body).to include("No policy yet")
      expect(response.body).to include("an invoice needs no approval")
    end

    it "are written with their levels, a blank row of the form ignored" do
      get new_accounting_settings_approval_policy_path
      expect(response).to have_http_status(:ok)

      post accounting_settings_approval_policies_path, params: valid_params

      expect(response).to redirect_to(accounting_settings_approval_policies_path)
      policy = Approvals::Policy.sole
      expect(policy).to have_attributes(name: "Over 1,000", priority: 10, reminder_hours: [ 24, 48 ], conditions: { "min_amount" => "1000", "currencies" => [ "EUR" ] })
      expect(policy.steps.map { |s| [ s.position, s.mode, s.approver_roles, s.approver_user_ids, s.service_hours, s.escalate_to_id ] }).to eq(
        [ [ 1, "any_of", %w[accountant], [], 48, owner.id ], [ 2, "all_of", [], [ owner.id ], nil, nil ] ]
      )
      follow_redirect!
      expect(response.body).to include("Over 1,000", "Level 1", "Level 2")
    end

    it "are refused with the reason, and the form keeps what was typed" do
      post accounting_settings_approval_policies_path, params: valid_params.merge(steps: { "0" => { mode: "any_of", approver_roles: [ "" ], approver_user_ids: [ "" ], service_hours: "" } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("at least one level").and include("Over 1,000")
      expect(Approvals::Policy.count).to eq(0)
    end

    it "are edited, with a blank level to add one" do
      post accounting_settings_approval_policies_path, params: valid_params
      policy = Approvals::Policy.sole

      get edit_accounting_settings_approval_policy_path(policy)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Over 1,000").and include('name="steps[2]')

      patch accounting_settings_approval_policy_path(policy), params: valid_params.deep_merge(policy: { name: "Renamed" })

      expect(policy.reload.name).to eq("Renamed")
      expect(Approvals::Policy.count).to eq(1)
    end

    it "become a new version when their levels change under requests, and say so" do
      post accounting_settings_approval_policies_path, params: valid_params
      policy = Approvals::Policy.sole
      invoice = create(:invoice, :supplier, fiscal_year: create(:fiscal_year, status: :open)).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "2000.00") }
      Approvals::Submit.call(invoice: invoice, user: nil)

      patch accounting_settings_approval_policy_path(policy), params: valid_params.merge(steps: { "0" => { mode: "any_of", approver_roles: [ "", "admin" ] } })

      expect(response).to redirect_to(accounting_settings_approval_policies_path)
      expect(flash[:notice]).to match(/version 2/i)
      expect(policy.reload.active).to be false
      expect(Approvals::Policy.active.sole.version).to eq(2)
      follow_redirect!
      expect(response.body).to include("Retired")
    end
  end

  describe "the delegations" do
    let(:today) { Date.current }
    let(:params) { { delegation: { delegator_id: owner.id, delegate_id: accountant.id, starts_on: today.to_s, ends_on: (today + 7).to_s, reason: "Holiday", policy_ids: [ "" ] } } }

    it "are listed for the owners, with who stands in for whom and until when" do
      Approvals::Delegation.create!(delegator: owner, delegate: accountant, starts_on: today, ends_on: today + 5, reason: "Holiday")

      get accounting_settings_approval_delegations_path

      expect(response.body).to include("Olga Owner", "Alice Accountant", "Holiday")
    end

    it "are made between two people who can approve, for all the policies when none is picked" do
      post accounting_settings_approval_delegations_path, params: params

      expect(response).to redirect_to(accounting_settings_approval_delegations_path)
      expect(Approvals::Delegation.sole).to have_attributes(delegator: owner, delegate: accountant, reason: "Holiday", policy_ids: [])
    end

    it "are refused to someone who cannot approve" do
      post accounting_settings_approval_delegations_path, params: params.deep_merge(delegation: { delegate_id: assistant.id })

      expect(flash[:alert]).to match(/cannot approve/i)
      expect(Approvals::Delegation.count).to eq(0)
    end

    it "end when they are deleted" do
      delegation = Approvals::Delegation.create!(delegator: owner, delegate: accountant, starts_on: today, ends_on: today + 5, reason: "Holiday")

      delete accounting_settings_approval_delegation_path(delegation)

      expect(Approvals::Delegation.count).to eq(0)
      expect(Accounting::AuditLog.for_record(delegation).for_action("destroy")).to exist
    end

    it "are the owner's: an accountant cannot make one" do
      sign_in accountant

      post accounting_settings_approval_delegations_path, params: params

      expect(Approvals::Delegation.count).to eq(0)
    end
  end
end

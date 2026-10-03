require "rails_helper"

# F01 review (point 12): the dashboard has no policy of its own. That is a choice: its indicators (treasury, drafts to
# validate, key figures) are covered by "consult the reports", which every role has. If a role ever loses
# `reports.view`, this spec must be revisited together with DashboardController.
RSpec.describe "The dashboard, role by role", type: :request do
  include_context "with entity"

  UserEntity.roles.each_key do |role|
    it "is shown to a #{role}" do
      user = create(:user)
      create(:user_entity, role.to_sym, user: user, entity: entity)
      sign_in user

      get accounting_root_path

      expect(response).to have_http_status(:ok)
    end
  end

  it "is the reports permission that justifies it: every role holds it" do
    expect(UserEntity.roles.keys.map(&:to_sym)).to all(satisfy { |role| Permissions.allowed?(role, "reports.view") })
  end

  it "is closed to someone with no access to the entity" do
    sign_in create(:user)

    get accounting_root_path

    expect(response).not_to have_http_status(:ok)
  end
end

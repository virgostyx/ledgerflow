require "rails_helper"

RSpec.describe "Notification preferences (F08)", type: :request do
  include_context "with entity"

  let(:user) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }

  before { sign_in user }

  it "starts with e-mails on and the daily summary off, and saves the choice of the person for their own access only" do
    expect(membership).to have_attributes(notify_by_email: true, notify_daily_digest: false)
    other = create(:user_entity, :accountant, user: create(:user), entity: entity)

    get edit_accounting_notification_preferences_path
    expect(response.body).to include("Send me an e-mail").and include("summary of my open tasks")

    patch accounting_notification_preferences_path, params: { user_entity: { notify_by_email: "0", notify_daily_digest: "1" } }

    expect(membership.reload).to have_attributes(notify_by_email: false, notify_daily_digest: true)
    expect(other.reload).to have_attributes(notify_by_email: true, notify_daily_digest: false)
  end

  it "does not touch anything else of the access, whatever the form sends" do
    patch accounting_notification_preferences_path, params: { user_entity: { notify_by_email: "1", role: "admin" } }

    expect(membership.reload.role).to eq("accountant")
  end

  it "is closed when the feature is off" do
    entity.update!(features: { "f08" => false })
    get edit_accounting_notification_preferences_path

    expect(response).to redirect_to(accounting_root_path)
  end
end

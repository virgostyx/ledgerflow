require "rails_helper"

# B03b: the thresholds of the review alerts and the switch of the visits are the owner's, whole numbers within bounds, and every change is recorded.
RSpec.describe "Settings of the report of changes", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  def patch_settings(**values) = patch(accounting_settings_entity_path, params: { entity: values })

  it "lets the owner set the thresholds and the visits, and records each change" do
    sign_in owner

    patch_settings(changes_late_days: "30", changes_reversals_per_author: "8", changes_mass_import: "100", changes_unletterings: "5", track_visits: "0")

    expect(entity.reload).to have_attributes(changes_late_days: 30, changes_reversals_per_author: 8, changes_mass_import: 100, changes_unletterings: 5, track_visits: false)
    logs = Accounting::AuditLog.for_record(entity).for_action("changes_option_changed")
    expect(logs.map { |l| l.payload["option"] }).to match_array(%w[changes_late_days changes_reversals_per_author changes_mass_import changes_unletterings track_visits])
    expect(logs.find { |l| l.payload["option"] == "changes_late_days" }.payload).to include("from" => 15, "to" => 30)
  end

  it "is not an accountant's to change" do
    sign_in accountant
    patch_settings(changes_late_days: "1")

    expect(entity.reload.changes_late_days).to eq(15)
  end

  it "keeps whole numbers from 1 to 1000" do
    sign_in owner

    [ "0", "-3", "1001", "abc" ].each do |bad|
      patch_settings(changes_late_days: bad)
      expect(entity.reload.changes_late_days).to eq(15), bad
    end
  end

  it "shows the fields on the screen of the company when the feature is on" do
    sign_in owner
    entity.update!(features: entity.features.merge("b03b" => true))

    get edit_accounting_settings_entity_path

    expect(response.body).to include("Late entry").and include("entity_changes_late_days")
  end

  it "uses the thresholds of the company in the report" do
    entity.update!(changes_late_days: 3)

    expect(Changes::Alerts.thresholds_of(entity)).to include(late_days: 3, reversals_per_author: 5, mass_import: 50, unletterings: 3)
  end
end

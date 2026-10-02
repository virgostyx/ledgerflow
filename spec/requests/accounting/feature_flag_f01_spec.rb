require "rails_helper"

# F01 ships behind a per-entity flag: off hides its screens, never the safeguards, and never touches the data.
RSpec.describe "Feature flag f01", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:owner_membership)      { create(:user_entity, :admin,      user: owner,      entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { sign_in owner }

  context "when the flag is off" do
    before { entity.update!(features: { "f01" => false }) }

    it "closes the Periods screen" do
      get accounting_period_locks_path

      expect(response).to redirect_to(accounting_root_path)
      expect(flash[:alert]).to match(/not enabled/i)
    end

    it "does not lock a period through the screen" do
      expect {
        post accounting_period_locks_path, params: { period_lock: { starts_on: "2026-03-01", ends_on: "2026-03-31" } }
      }.not_to change(Accounting::PeriodLock, :count)
    end

    it "closes Users and roles, and invites nobody" do
      get accounting_settings_memberships_path
      expect(response).to redirect_to(accounting_root_path)

      expect {
        post accounting_settings_memberships_path, params: { membership: { email: "x@example.com", full_name: "X", role: "manager" } }
      }.not_to change(UserEntity, :count)
    end

    it "hides the entries of F01 from the menus and the settings" do
      get accounting_settings_root_path
      expect(response.body).not_to include(accounting_settings_memberships_path)

      get accounting_journal_entries_path
      expect(response.body).not_to include(accounting_period_locks_path)
    end

    it "hides the four-eyes fields of the entity form" do
      get edit_accounting_settings_entity_path

      expect(response.body).not_to include("entity[four_eyes]")
    end

    it "keeps the safeguards: a locked period still refuses to be posted in, and the last owner stays protected" do
      create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month)
      entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2)

      expect(Accounting::PostJournalEntry.call(entry: entry)).to be_failure
      expect(owner_membership.update(role: :accountant)).to be false
    end

    it "does not show the locked-period banner, whatever the data says" do
      create(:period_lock, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month, lock_reason: "January closed")
      entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2)

      get accounting_journal_entry_path(entry)

      expect(response.body).not_to include("January closed")
    end

    it "leaves the existing locks as they were" do
      lock = create(:period_lock)

      get accounting_period_locks_path

      expect(lock.reload).to be_locked
    end
  end

  context "when the flag is on" do
    it "shows the Periods entry in the menu" do
      get accounting_journal_entries_path

      expect(response.body).to include(accounting_period_locks_path)
    end
  end

  describe "turning it on" do
    before { entity.update!(features: { "f01" => false }) }

    it "is the owner's call, in the entity settings" do
      get edit_accounting_settings_entity_path
      expect(response.body).to include("entity[features][f01]")

      patch accounting_settings_entity_path, params: { entity: { features: { f01: "1" } } }

      expect(entity.reload.feature?(:f01)).to be true
      get accounting_period_locks_path
      expect(response).to have_http_status(:ok)
    end

    it "can be turned off again by the owner" do
      entity.update!(features: { "f01" => true })

      patch accounting_settings_entity_path, params: { entity: { features: { f01: "0" } } }

      expect(entity.reload.feature?(:f01)).to be false
    end

    it "ignores an accountant who sends it" do
      sign_out owner
      sign_in accountant

      patch accounting_settings_entity_path, params: { entity: { features: { f01: "1" } } }

      expect(entity.reload.feature?(:f01)).to be false
    end

    it "ignores a feature that does not exist" do
      patch accounting_settings_entity_path, params: { entity: { features: { f99: "1" } } }

      expect(entity.reload.features).not_to have_key("f99")
      expect(entity.feature?(:f01)).to be false
    end
  end
end

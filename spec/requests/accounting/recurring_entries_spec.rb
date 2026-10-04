require "rails_helper"

# F07 §10, screen "Recurring": list with next due date, last run and status, create, pause and resume, skip an occurrence, preview of the
# twelve next due dates, the owner's approval of the post mode.
RSpec.describe "Recurring entries", type: :request do
  include_context "with_pcmn_accounts"

  let!(:fiscal_year) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2027, 12, 31), status: :open, entity: entity) }
  let!(:misc)       { create(:journal, journal_type: :misc) }
  let(:owner)       { create(:user, role: :admin) }
  let(:accountant)  { create(:user, role: :accountant) }
  let(:assistant)   { create(:user, role: :auditor) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let(:template) do
    Accounting::EntryTemplate.new(name: "Rent", journal: misc, description: "Rent").tap do |t|
      t.lines.build(account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "Rent", position: 0)
      t.lines.build(account: account_440, side: :credit, amount_kind: :percent, percentage: 100, label: "Landlord", position: 1)
      t.save!
    end
  end
  let!(:recurring) do
    Accounting::RecurringEntry.create!(name: "Office rent", entry_template: template, frequency: :monthly, day_of_month: 1, starts_on: Date.new(2026, 11, 1),
                                       base_amount: 1000, indexation_percent: 3)
  end

  before { sign_in accountant }

  it "lists them with the next due date, the status and the preview of the twelve next" do
    get accounting_recurring_entries_path

    expect(response.body).to include("Office rent").and include("01/11/2026").and include("Active")
    expect(response.body).to include("01/10/2027") # the twelfth due date
    expect(response.body).to include("1,030.00") # the indexed amount of January 2027
  end

  it "shows the last run" do
    travel_to(Date.new(2026, 11, 1)) { Accounting::GenerateRecurringEntries.call }
    get accounting_recurring_entries_path

    expect(response.body).to include("Generated")
  end

  it "creates one" do
    expect {
      post accounting_recurring_entries_path, params: { accounting_recurring_entry: {
        name: "Bank charges", entry_template_id: template.id, frequency: "quarterly", day_of_month: "", starts_on: "2026-12-01", base_amount: "45", lead_days: "0"
      } }
    }.to change(Accounting::RecurringEntry, :count).by(1)

    expect(Accounting::RecurringEntry.last).to have_attributes(day_of_month: nil, frequency: "quarterly", created_by_id: accountant.id)
  end

  it "shows what is wrong with a schedule" do
    post accounting_recurring_entries_path, params: { accounting_recurring_entry: { name: "", entry_template_id: template.id, starts_on: "2026-12-01" } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "updates and deletes one" do
    patch accounting_recurring_entry_path(recurring), params: { accounting_recurring_entry: { base_amount: "1100" } }
    expect(recurring.reload.base_amount).to eq(1100)

    expect { delete accounting_recurring_entry_path(recurring) }.to change(Accounting::RecurringEntry, :count).by(-1)
  end

  it "pauses and resumes, and audits it" do
    post pause_accounting_recurring_entry_path(recurring)
    expect(recurring.reload).to be_paused

    post resume_accounting_recurring_entry_path(recurring)
    expect(recurring.reload).to be_active
    expect(Accounting::AuditLog.where(auditable_type: "Accounting::RecurringEntry", action: %w[recurring_paused recurring_resumed]).count).to eq(2)
  end

  it "skips the next occurrence without making an entry" do
    post skip_accounting_recurring_entry_path(recurring)

    expect(recurring.reload.next_due_on).to eq(Date.new(2026, 12, 1))
    expect(Accounting::RecurringRun.sole).to have_attributes(status: "skipped", due_on: Date.new(2026, 11, 1), journal_entry_id: nil)
  end

  describe "the post mode" do
    it "is the owner's to allow" do
      post approve_post_accounting_recurring_entry_path(recurring)
      expect(recurring.reload).to be_mode_draft

      sign_in owner
      post approve_post_accounting_recurring_entry_path(recurring)
      expect(recurring.reload).to be_mode_post
    end

    it "offers the button to the owner only" do
      get accounting_recurring_entries_path
      expect(response.body).not_to include("Let it post by itself")

      sign_in owner
      get accounting_recurring_entries_path
      expect(response.body).to include("Let it post by itself")
    end
  end

  it "is closed to a role that cannot manage them" do
    sign_in assistant
    get accounting_recurring_entries_path

    expect(response).not_to have_http_status(:ok)
  end
end

require "rails_helper"

# B01b "spec système du parcours de la sélection à l'export": from the invoices that fall due to the file and the statement that it was loaded in the bank, through the
# people who each have their part - the one who prepares, the one who authorizes, the one who exports.
RSpec.describe "The payments, from the selection to the file", type: :system do
  include_context "with approvable batch"

  let(:exporter) { create(:user, full_name: "Eve Exporter").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  before do
    owner
    profile # the owner has recorded how the bank takes the file (Settings > Bank profiles)
    Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin])
    posted(due: Date.current + 2)
  end

  it "takes an invoice that falls due to the file, each step by the person who has it" do
    login_as preparer, scope: :user
    visit accounting_payments_path
    click_link "New batch", match: :first
    fill_in "execution_date", with: execution.iso8601
    click_button "Show what falls due"
    expect(page).to have_content("ACH2026/0001")
    expect(page).not_to have_content("BE68539007547034")
    click_button "Make the batch"

    expect(page).to have_content("PAY-2026-0001").and have_content("BE68 **** **** 7034")
    expect(page).to have_content("Not put to approval yet")
    click_button "Ask for the approval"
    expect(page).to have_content("Waiting for approval")
    expect(page).not_to have_button("Authorize") # the one who prepared it does not authorize it

    login_as authorizer, scope: :user
    visit accounting_payments_path
    click_link "PAY-2026-0001"
    click_button "Authorize"
    expect(page).to have_content("Make the file").or have_button("Make the file")

    login_as exporter, scope: :user
    visit accounting_payments_path
    click_link "PAY-2026-0001"
    click_button "Make the file"
    expect(page).to have_content("Compare these values with the summary of your bank")
    expect(page).to have_content("1210.00").and have_content("Message id").and have_link("Download the file")
    click_button "I loaded the file in my bank"

    expect(page).to have_content("Loaded in the bank by Eve Exporter")
    expect(Payments::Batch.last).to be_submitted
    expect(Accounting::AuditLog.for_record(Payments::Batch.last).pluck(:action)).to include("approval_submitted", "approval_approved", "payment_batch_exported", "payment_batch_submitted")
  end
end

require "rails_helper"

# The analytical accounts BudgetFlow sets on its invoices (project, budget line) are not the accountant's to change: to change
# them the invoice goes back to the project manager. The other axes stay free.
RSpec.describe "Invoice analytical accounts set by BudgetFlow", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:admin) { create(:user, role: :admin) }
  let!(:membership) { create(:user_entity, :admin, user: admin, entity: entity) }
  let!(:supplier) { create(:partner, :supplier, external_ref: "BF-P-1") }
  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:proj_axis) { Accounting::AnalyticalAxis.find_or_create_by!(code: "PROJ") { |a| a.label_fr = "Projects" } }
  let!(:budg_axis) { Accounting::AnalyticalAxis.find_or_create_by!(code: "BUDG") { |a| a.label_fr = "Budget lines" } }
  let!(:act_axis)  { Accounting::AnalyticalAxis.find_or_create_by!(code: "ACT") { |a| a.label_fr = "Activities" } }
  let!(:activity)  { create(:analytical_account, analytical_axis: act_axis, code: "TRAIN", label_fr: "Training") }

  let!(:invoice) do
    Accounting::ExternalAnalytics.upsert("bf-project-1", code: "PRODEM", name: "PRODEM", budget_lines: [ { ref: "bf-subline-5", code: "1.1.1", label: "Staff" },
                                                                                                         { ref: "bf-subline-6", code: "1.1.2", label: "Driver" } ])
    Accounting::ExternalInvoice.upsert(
      external_ref: "BF-I-1", partner_external_ref: "BF-P-1", invoice_type: "supplier", invoice_date: Date.current.to_s, post: false,
      project_ref: "bf-project-1", budget_line_ref: "bf-subline-5",
      lines: [ { account_code: "604000", description: "Consulting", quantity: "1", unit_price: "100", vat_rate: "21" } ]
    ).invoice
  end
  let(:line)     { invoice.lines.first }
  let(:budget)   { line.analytical_annotations.find_by!(analytical_axis: budg_axis) }
  let(:other_budget_line) { Accounting::AnalyticalAccount.find_by!(external_ref: "bf-subline-6") }

  before { sign_in admin }

  def edit_lines(annotations, extra_lines = {})
    patch accounting_invoice_path(invoice), params: { accounting_invoice: { lines_attributes: { "0" => { id: line.id, analytical_annotations_attributes: annotations } }.merge(extra_lines) } }
  end

  def accounts_of(inv) = inv.reload.lines.map { |l| l.analytical_annotations.map { |a| a.analytical_account.code }.sort }

  it "ignores a change of the budget line" do
    edit_lines("0" => { id: budget.id, analytical_axis_id: budg_axis.id, analytical_account_id: other_budget_line.id })

    expect(accounts_of(invoice)).to eq([ %w[PRODEM PRODEM-1.1.1] ])
  end

  it "ignores the removal of the project or of the budget line" do
    edit_lines("0" => { id: budget.id, analytical_axis_id: budg_axis.id, _destroy: "1" })

    expect(accounts_of(invoice)).to eq([ %w[PRODEM PRODEM-1.1.1] ])
  end

  it "ignores a second account on an axis BudgetFlow already filled" do
    edit_lines("0" => { analytical_axis_id: proj_axis.id, analytical_account_id: other_budget_line.id })

    expect(accounts_of(invoice)).to eq([ %w[PRODEM PRODEM-1.1.1] ])
  end

  it "lets the accountant choose the other axes" do
    edit_lines("0" => { analytical_axis_id: act_axis.id, analytical_account_id: activity.id })

    expect(accounts_of(invoice)).to eq([ %w[PRODEM PRODEM-1.1.1 TRAIN] ])
  end

  it "gives the same project and budget line to a line the accountant adds" do
    edit_lines({}, "1" => { description: "Extra", account_id: account_604.id, quantity: "1", unit_price: "10", vat_rate: "21" })

    expect(accounts_of(invoice)).to eq([ %w[PRODEM PRODEM-1.1.1] ] * 2)
  end

  it "shows them without a choice, and keeps the free axes selectable" do
    get edit_accounting_invoice_path(invoice)

    expect(response.body).to include("PRODEM-1.1.1").and include("set by BudgetFlow")
    expect(response.body).not_to include("<option value=\"#{other_budget_line.id}\"") # no choice offered on the locked axes
    expect(response.body).to include("Training")
  end

  it "leaves an invoice typed in LedgerFlow entirely to the accountant" do
    typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
    typed_line = create(:invoice_line, invoice: typed, account: account_604)
    project = create(:analytical_account, analytical_axis: proj_axis, code: "FREE", label_fr: "Free", external_ref: "bf-project-9")

    patch accounting_invoice_path(typed), params: { accounting_invoice: { lines_attributes: { "0" => { id: typed_line.id,
          analytical_annotations_attributes: { "0" => { analytical_axis_id: proj_axis.id, analytical_account_id: project.id } } } } } }

    expect(typed_line.reload.analytical_annotations.map { |a| a.analytical_account.code }).to eq(%w[FREE])
  end
end

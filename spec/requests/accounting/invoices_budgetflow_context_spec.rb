require "rails_helper"

RSpec.describe "Invoice BudgetFlow context", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:admin) { create(:user, role: :admin) }
  let!(:membership) { create(:user_entity, :admin, user: admin, entity: entity) }
  let(:supplier) { create(:partner, :supplier) }
  let(:invoice) do
    create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year,
           external_project_name: "Water Access Zambia", external_budget_line: "3.2.1")
  end

  before { sign_in admin }

  context "when the entity uses BudgetFlow" do
    before { entity.update!(budgetflow_enabled: true) }

    it "shows the project and the budget line on the invoice and its edit form" do
      get accounting_invoice_path(invoice)
      expect(response.body).to include("From BudgetFlow").and include("Water Access Zambia").and include("3.2.1")

      get edit_accounting_invoice_path(invoice)
      expect(response.body).to include("From BudgetFlow").and include("3.2.1")
    end

    it "shows nothing for an invoice without context" do
      plain = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)

      get accounting_invoice_path(plain)

      expect(response.body).not_to include("From BudgetFlow")
    end
  end

  context "when the entity does not use BudgetFlow" do
    it "shows nothing of it" do
      get accounting_invoice_path(invoice)

      expect(response.body).not_to include("BudgetFlow")
      expect(response.body).not_to include("Water Access Zambia")
    end
  end
end

require "rails_helper"

# B01a §4: the approvals table - delays, refusals, late requests, by approver and by supplier. For those who may see the audit trail.
RSpec.describe "Approvals statistics (B01a)", type: :request do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:owner)       { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant)  { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)   { create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:reader)      { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:auditor)     { create(:user).tap { |u| create(:user_entity, :auditor, user: u, entity: entity) } }

  before do
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin accountant], service_hours: 24)
    sign_in owner
  end

  def request_for(supplier_name)
    invoice = create(:invoice, :supplier, partner: create(:partner, :supplier, name: supplier_name), fiscal_year: fiscal_year).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "100.00") }
    Approvals::Submit.call(invoice: invoice, user: nil)[:request]
  end

  def decide(request, user, kind, **extra)
    Approvals::Decide.call(request: request, user: user, decision: kind, content_fingerprint: request.content_fingerprint, comment: ("because" unless kind == :approved), **extra)
  end

  describe "the right" do
    it "is closed when the feature is off" do
      entity.update!(features: entity.features.merge("b01a" => false))

      get statistics_accounting_approvals_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "is for those who may see the audit trail: the owner, the accountant, the external auditor" do
      [ owner, accountant, auditor ].each do |user|
        sign_in user
        get statistics_accounting_approvals_path
        expect(response).to have_http_status(:ok), user.full_name.to_s
      end
    end

    it "is closed to an assistant and to a reader" do
      [ assistant, reader ].each do |user|
        sign_in user
        get statistics_accounting_approvals_path
        expect(response).not_to have_http_status(:ok)
      end
    end
  end

  describe "the figures" do
    before do
      decide(request_for("Acme Ltd"), accountant, :approved)
      decide(request_for("Acme Ltd"), owner, :rejected)
      decide(request_for("Beta SA"), accountant, :changes_requested)
      request_for("Beta SA") # still waiting
    end

    it "shows what was submitted, the refusal rate and what waits" do
      get statistics_accounting_approvals_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Requests submitted").and include("Refusal rate").and include("Waiting now")
      expect(body).to match(/Refusal rate.*?67 %/m) # 2 refused or sent back, out of 3 decided
    end

    it "lists each approver with their decisions, and each supplier with theirs" do
      get statistics_accounting_approvals_path

      expect(response.body).to include("Alice Accountant", "Olga Owner", "Acme Ltd", "Beta SA")
    end

    it "takes the period asked for, and says when it is empty" do
      get statistics_accounting_approvals_path, params: { from: (Date.current + 10).to_s, to: (Date.current + 20).to_s }

      expect(response.body).to include("No request in this period")
    end

    it "falls back on the last 90 days when the dates are not dates" do
      get statistics_accounting_approvals_path, params: { from: "yesterday-ish", to: "??" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Requests submitted")
    end
  end

  describe "the way in" do
    it "is linked from To approve, for those who may open it" do
      get accounting_approvals_path
      expect(response.body).to include("Statistics")
      expect(response.body).to include(statistics_accounting_approvals_path)
    end
  end
end

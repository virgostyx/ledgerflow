require "rails_helper"

# F07 §10, screens of the entry templates: list, create, edit, delete, examples, "New entry from a template".
RSpec.describe "Entry templates", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership) { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:misc) { create(:journal, journal_type: :misc) }

  def make_template
    Accounting::EntryTemplate.new(name: "Rent", journal: misc, description: "Rent {mois}").tap do |t|
      t.lines.build(account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "Rent", position: 0)
      t.lines.build(account: account_440, side: :credit, amount_kind: :percent, percentage: 100, label: "Landlord", position: 1)
      t.save!
    end
  end

  before { sign_in accountant }

  it "lists the templates" do
    make_template
    get accounting_entry_templates_path

    expect(response.body).to include("Rent").and include("Add the examples")
  end

  it "creates a template with its lines" do
    expect {
      post accounting_entry_templates_path, params: { accounting_entry_template: {
        name: "Insurance", journal_id: misc.id, description: "Premium {année}",
        lines_attributes: { "0" => { account_id: account_604.id, side: "debit", amount_kind: "fixed", amount: "100", label: "Premium" },
                            "1" => { account_id: account_440.id, side: "credit", amount_kind: "fixed", amount: "100", label: "Insurer" },
                            "2" => { account_id: "" } }
      } }
    }.to change(Accounting::EntryTemplate, :count).by(1)

    expect(Accounting::EntryTemplate.last.lines.size).to eq(2)
  end

  it "shows what is wrong with a template" do
    post accounting_entry_templates_path, params: { accounting_entry_template: { name: "", journal_id: misc.id } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "updates and deletes a template" do
    template = make_template
    patch accounting_entry_template_path(template), params: { accounting_entry_template: { name: "Office rent" } }
    expect(template.reload.name).to eq("Office rent")

    expect { delete accounting_entry_template_path(template) }.to change(Accounting::EntryTemplate, :count).by(-1)
  end

  it "adds the examples" do
    %w[610100 440000].each { |code| Accounting::Account.find_by(code: code) || create(:account, code: code, label_fr: code, account_class: code[0].to_i, entity: entity) }

    post examples_accounting_entry_templates_path

    expect(Accounting::EntryTemplate.pluck(:name)).to include("Rent")
    expect(flash[:notice]).to match(/\d+ example template/)
  end

  describe "a new entry from a template" do
    let!(:template) { make_template }

    it "asks for the date and the base amount" do
      get entry_accounting_entry_template_path(template)

      expect(response.body).to include("Amount").and include("Date")
    end

    it "creates the draft and opens it" do
      expect {
        post create_entry_accounting_entry_template_path(template), params: { date: (fiscal_year.start_date + 40).to_s, base_amount: "950" }
      }.to change(Accounting::JournalEntry.draft, :count).by(1)

      expect(response).to redirect_to(accounting_journal_entry_path(Accounting::JournalEntry.order(:id).last))
    end

    it "says what is missing" do
      post create_entry_accounting_entry_template_path(template), params: { date: (fiscal_year.start_date + 40).to_s }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter the amount")
    end
  end

  it "is closed to a role that cannot manage templates" do
    sign_in assistant
    get accounting_entry_templates_path

    expect(response).not_to have_http_status(:ok)
  end
end

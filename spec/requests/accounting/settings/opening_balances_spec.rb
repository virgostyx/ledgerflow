require "rails_helper"

RSpec.describe "Accounting::Settings::OpeningBalances", type: :request do
  include_context "with entity"
  include_context "with_open_fiscal_year"

  let(:admin)   { create(:user, role: :admin) }
  let(:manager) { create(:user, role: :manager) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  let!(:misc_journal) { create(:journal, journal_type: :misc, code: "OD", sequence_prefix: "OD") }
  let!(:receivable)   { create(:account, code: "400000", account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true) }
  let!(:payable)      { create(:account, code: "440000", account_class: 4, account_type: :liability, normal_balance: :credit, reconcilable: true) }
  let!(:transit)      { create(:account, code: "499000", account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:capital)      { create(:account, code: "100000", account_class: 1, account_type: :equity, normal_balance: :credit) }

  def csv_file(content, name)
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: name)
  end

  let(:balances) { csv_file("account_code,debit,credit\n400000,300,0\n100000,0,300\n", "balances.csv") }
  let(:invoices) do
    csv_file("type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\ncustomer,Acme SA,,A1,2025-11-15,2025-12-15,300\n", "invoices.csv")
  end

  before { sign_in admin }

  describe "GET /accounting/settings/opening_balance" do
    it "shows the upload form for the first fiscal year" do
      get accounting_settings_opening_balance_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Opening Balances").and include("balances_file")
    end

    it "refuses a manager" do
      sign_in manager
      get accounting_settings_opening_balance_path
      expect(response).to redirect_to(accounting_root_path)
    end

    it "explains when the opening balances were already imported" do
      create(:journal_entry, journal: misc_journal, fiscal_year: fiscal_year, source_type: Accounting::JournalEntry::OPENING_SOURCE)
      get accounting_settings_opening_balance_path
      expect(response.body).to include("already imported")
    end
  end

  describe "POST /accounting/settings/opening_balance" do
    let(:files) { { balances_file: balances, invoices_file: invoices } }

    it "checks the files without writing anything" do
      expect { post accounting_settings_opening_balance_path, params: files.merge(mode: "check") }
        .not_to change(Accounting::JournalEntry, :count)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Check passed").and include("1 open invoice")
    end

    it "imports the opening balances" do
      expect { post accounting_settings_opening_balance_path, params: files.merge(mode: "import") }
        .to change(Accounting::JournalEntry, :count).by(2).and change(Accounting::Invoice, :count).by(1)
      expect(response.body).to include("Import complete")
    end

    it "lists the errors and writes nothing" do
      bad = csv_file("account_code,debit,credit
400000,300,0
100000,0,100
", "balances.csv")
      expect { post accounting_settings_opening_balance_path, params: { balances_file: bad, invoices_file: invoices, mode: "import" } }
        .not_to change(Accounting::JournalEntry, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("not balanced")
    end

    it "asks for both files" do
      post accounting_settings_opening_balance_path, params: { balances_file: balances, mode: "check" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose both files")
    end

    it "refuses a manager" do
      sign_in manager
      post accounting_settings_opening_balance_path, params: files.merge(mode: "import")
      expect(response).to redirect_to(accounting_root_path)
      expect(Accounting::Invoice.count).to eq(0)
    end
  end

  describe "GET /accounting/settings/opening_balance/template" do
    it "downloads the balances template" do
      get template_accounting_settings_opening_balance_path(kind: "balances")
      expect(response.media_type).to eq("text/csv")
      expect(response.body.lines.first.strip).to eq("account_code,debit,credit")
    end

    it "downloads the invoices template" do
      get template_accounting_settings_opening_balance_path(kind: "invoices")
      expect(response.body.lines.first.strip).to eq("type,partner_name,partner_vat,number,invoice_date,due_date,open_amount")
    end
  end
end

require "rails_helper"

RSpec.describe "The closing checklist on a fiscal year", type: :request do
  include_context "with_open_fiscal_year"

  let(:admin)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:admin_membership)      { create(:user_entity, :admin, user: admin, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:journal) { create(:journal, :purchase) }

  before do
    entity.update!(vat_regime: :franchise)
    sign_in admin
  end

  def page = Nokogiri::HTML(response.body)
  def close_button = page.at_css("form[action='#{close_accounting_fiscal_year_path(fiscal_year)}'] [type=submit], form[action='#{close_accounting_fiscal_year_path(fiscal_year)}'] button")

  it "lists the checks with what is left to do" do
    create(:invoice, :draft, fiscal_year: fiscal_year)
    get accounting_fiscal_year_path(fiscal_year)

    expect(response.body).to include("Closing checklist", "Draft invoices", "1 invoice")
  end

  it "links each problem to the screen where it is fixed" do
    create(:invoice, :draft, fiscal_year: fiscal_year)
    get accounting_fiscal_year_path(fiscal_year)

    expect(page.at_css("[data-check='draft_invoices'] a")['href']).to include(accounting_sales_path)
  end

  it "asks to confirm the closing with the number of warnings left" do
    create(:invoice, :draft, fiscal_year: fiscal_year)
    get accounting_fiscal_year_path(fiscal_year)

    expect(close_button['data-turbo-confirm']).to include('1 warning')
  end

  it "does not offer the closing while a check blocks it, and says why" do
    create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 3)
    get accounting_fiscal_year_path(fiscal_year)

    expect(page.at_css("form[action='#{close_accounting_fiscal_year_path(fiscal_year)}']")).to be_nil
    expect(response.body).to include("cannot be closed yet")
  end

  it "offers the closing when nothing blocks it" do
    get accounting_fiscal_year_path(fiscal_year)
    expect(page.at_css("form[action='#{close_accounting_fiscal_year_path(fiscal_year)}']")).to be_present
  end

  it "shows no checklist for a year that is already closed" do
    fiscal_year.update!(status: :closed, closed_at: Time.current, closed_by_id: admin.id)
    get accounting_fiscal_year_path(fiscal_year)
    expect(response.body).not_to include("Closing checklist")
  end
end

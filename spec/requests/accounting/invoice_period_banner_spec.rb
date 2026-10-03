require "rails_helper"

# F01: the banner of a locked period is on invoices as well as on entries.
RSpec.describe "Locked period banner on an invoice", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:month) { fiscal_year.start_date.beginning_of_month }
  let(:invoice) { create(:invoice, :draft, fiscal_year: fiscal_year, invoice_date: month + 10) }

  before { sign_in accountant }

  it "warns that the invoice sits in a locked period, says why and links to the periods" do
    create(:period_lock, starts_on: month, ends_on: month.end_of_month, lock_reason: "January closed")

    get accounting_invoice_path(invoice)

    expect(response.body).to include("locked period", "January closed", accounting_period_locks_path)
  end

  it "does not offer to post a draft of a locked period" do
    create(:period_lock, starts_on: month, ends_on: month.end_of_month)

    get accounting_invoice_path(invoice)

    expect(response.body).not_to include("Post invoice")
  end

  it "shows nothing for an invoice outside any locked period, and still offers to post it" do
    get accounting_invoice_path(invoice)

    expect(response.body).not_to include("locked period")
    expect(response.body).to include("Post invoice")
  end

  it "shows nothing while the feature is off for the entity" do
    create(:period_lock, starts_on: month, ends_on: month.end_of_month)
    entity.update!(features: entity.features.merge("f01" => false))

    get accounting_invoice_path(invoice)

    expect(response.body).not_to include("locked period")
  end
end

require "rails_helper"

# B02b, firm side: ask a client for the supporting documents of bank lines, see what came back, and choose whether the client sees bank lines. Right: portal.manage.
RSpec.describe "Portal document requests (firm side)", type: :request do
  include_context "with entity"
  include DocumentFiles

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:person)     { create(:portal_user) }
  let!(:bare)      { create(:bank_transaction, counterparty_name: "ACME Supplies", amount: BigDecimal("-50.00")) }
  let!(:covered)   { create(:bank_transaction, counterparty_name: "Already Covered") }

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: "director", capabilities: %w[documents.upload bank_lines.view questions.answer])
    document = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("covers")), filename: "a.pdf", user: accountant)[:document]
    Accounting::DocumentLink.create!(document: document, target: covered)
    sign_in accountant
  end

  it "offers the pending bank lines that have no document, not the others" do
    get accounting_portal_document_requests_path

    expect(response.body).to include("ACME Supplies")
    expect(response.body).not_to include("Already Covered")
  end

  it "asks the clients for the lines chosen" do
    expect { post accounting_portal_document_requests_path, params: { line_ids: [ bare.id ], message: "Please", due_on: "2026-05-01" } }
      .to change(Portal::DocumentRequestLine, :count).by(1)

    expect(response).to redirect_to(accounting_portal_document_requests_path)
    expect(Portal::DocumentRequest.sole).to have_attributes(message: "Please", due_on: Date.new(2026, 5, 1), requested_by_id: accountant.id)
  end

  it "says why it cannot ask" do
    post accounting_portal_document_requests_path, params: { line_ids: [] }
    follow_redirect!
    expect(response.body).to include("Choose at least one bank line")
  end

  it "shows what came back" do
    PortalAdmin::RequestDocuments.call(entity: entity, lines: [ bare ], by: accountant)
    Portal::DocumentRequestLine.sole.update!(state: "explained", answer_reason: "personal", answer_note: "my lunch")

    get accounting_portal_document_requests_path

    expect(response.body).to include("ACME Supplies", "explained", "personal")
  end

  it "shows the indicators, with a dash where there is nothing to measure" do
    get accounting_portal_document_requests_path
    expect(response.body).to include("Days from a bank movement to its document", "Documents given in time", "—")
  end

  it "lets the firm choose whether the clients see bank lines" do
    patch settings_accounting_portal_document_requests_path, params: { show_bank_lines: "0" }

    expect(entity.reload.portal_show_bank_lines).to be(false)
    expect(Accounting::AuditLog.where(action: "portal_bank_lines_visibility_changed").count).to eq(1)
  end

  it "is for those who manage the portal" do
    sign_in reader
    get accounting_portal_document_requests_path
    expect(response).to redirect_to(root_path).or have_http_status(:forbidden).or redirect_to(accounting_root_path)
    expect { post accounting_portal_document_requests_path, params: { line_ids: [ bare.id ] } }.not_to change(Portal::DocumentRequestLine, :count)
  end

  it "is closed while the feature is off" do
    entity.update!(features: { "b02b" => false })
    get accounting_portal_document_requests_path
    expect(response).to redirect_to(accounting_root_path)
  end
end

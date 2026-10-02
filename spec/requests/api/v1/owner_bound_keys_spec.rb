require "rails_helper"

# F01 criterion 1 and 8, through the API: a key does what its owner may do by hand, no more, checked at every call.
RSpec.describe "Api::V1 keys bound to their owner", type: :request do
  include_context "with_pcmn_accounts"
  include_context "with_open_fiscal_year"
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: "BF-P-1") }
  let(:line)      { { account_code: "604000", description: "Consulting", quantity: "2", unit_price: "50.00", vat_rate: "21" } }
  let(:payload)   { { partner_external_ref: "BF-P-1", invoice_type: "supplier", invoice_date: Date.current.to_s, lines: [ line ] } }

  def owner_with(role) = create(:user).tap { |user| create(:user_entity, role, user: user, entity: entity) }

  def key_for(owner, scopes: %w[invoices:read invoices:write])
    ApiClient.issue!(entity: entity, name: "BudgetFlow", scopes: scopes, owner: owner).last
  end

  def put_invoice(key, body, ref: "BF-I-1") = put("/api/v1/invoices/#{ref}", params: body, headers: { "Authorization" => "Bearer #{key}" }, as: :json)
  def invoice(ref = "BF-I-1") = Accounting::Invoice.external.find_by(external_ref: ref)

  describe "an owner who may not validate (assistant)" do
    let(:key) { key_for(owner_with(:assistant)) }

    it "cannot post an invoice, asked explicitly" do
      put_invoice(key, payload.merge(post: true))

      expect(response).to have_http_status(:forbidden)
      expect(invoice).to be_nil
    end

    it "cannot post it by leaving the default either (the API posts unless told otherwise)" do
      put_invoice(key, payload)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["reason"]).to match(/post/i)
      expect(invoice).to be_nil
    end

    it "can send a draft (post: false), which stays a draft" do
      put_invoice(key, payload.merge(post: false))

      expect(response).to have_http_status(:created)
      expect(invoice).to be_draft
    end

    it "cannot post by correcting a draft either" do
      put_invoice(key, payload.merge(post: false))

      put_invoice(key, payload.merge(post: true, description: "changed"))

      expect(response).to have_http_status(:forbidden)
      expect(invoice).to be_draft
    end
  end

  describe "cancelling a posted invoice (an API cancellation reverses its entry)" do
    def post_invoice_as_accountant
      put_invoice(key_for(owner_with(:accountant)), payload)
      expect(invoice).to be_posted
    end

    it "is refused to an owner who may not reverse entries" do
      post_invoice_as_accountant

      delete "/api/v1/invoices/BF-I-1", params: { reason: "x" }, headers: { "Authorization" => "Bearer #{key_for(owner_with(:assistant))}" }

      expect(response).to have_http_status(:forbidden)
      expect(invoice).to be_posted
    end

    it "is allowed to an owner who may" do
      post_invoice_as_accountant

      delete "/api/v1/invoices/BF-I-1", params: { reason: "x" }, headers: { "Authorization" => "Bearer #{key_for(owner_with(:accountant))}" }

      expect(response).to have_http_status(:ok)
    end

    it "is allowed to anyone when it is only a draft (nothing to reverse)" do
      put_invoice(key_for(owner_with(:assistant)), payload.merge(post: false))

      delete "/api/v1/invoices/BF-I-1", params: { reason: "x" }, headers: { "Authorization" => "Bearer #{key_for(owner_with(:assistant))}" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "an owner who may validate (accountant)" do
    it "posts as before" do
      put_invoice(key_for(owner_with(:accountant)), payload)

      expect(response).to have_http_status(:created)
      expect(invoice).to be_posted
    end
  end

  describe "an owner who may only read (reader)" do
    it "cannot even be given a write key" do
      expect { key_for(owner_with(:manager)) }.to raise_error(ActiveRecord::RecordInvalid, /invoices:write/)
    end

    it "reads with a read key" do
      get "/api/v1/invoices", headers: { "Authorization" => "Bearer #{key_for(owner_with(:manager), scopes: %w[invoices:read])}" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "rights removed after the key was issued" do
    it "refuses the very next call when the owner is demoted" do
      owner = owner_with(:accountant)
      key = key_for(owner)
      put_invoice(key, payload.merge(post: false))
      expect(response).to have_http_status(:created)

      UserEntity.find_by(user: owner, entity: entity).update!(role: :manager)
      put_invoice(key, payload.merge(post: false, description: "again"))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses everything when the owner's access is deactivated" do
      owner = owner_with(:accountant)
      key = key_for(owner)
      UserEntity.find_by(user: owner, entity: entity).update!(active: false)

      get "/api/v1/invoices", headers: { "Authorization" => "Bearer #{key}" }

      expect(response).to have_http_status(:forbidden)
    end

    it "stops posting when the owner is moved from accountant to assistant" do
      owner = owner_with(:accountant)
      key = key_for(owner)
      UserEntity.find_by(user: owner, entity: entity).update!(role: :assistant)

      put_invoice(key, payload)

      expect(response).to have_http_status(:forbidden)
      expect(invoice).to be_nil
    end
  end

  describe "a key issued before F01 (no owner)" do
    it "keeps working exactly as before" do
      key = ApiClient.issue!(entity: entity, name: "BudgetFlow", scopes: %w[invoices:read invoices:write]).last

      put_invoice(key, payload)

      expect(response).to have_http_status(:created)
      expect(invoice).to be_posted
    end
  end
end

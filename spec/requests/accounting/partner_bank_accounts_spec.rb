require "rails_helper"

# B01b, the screens: the bank accounts of the suppliers, to register, to verify, to block, with what happened to each.
RSpec.describe "Supplier bank details (B01b)", type: :request do
  include_context "with entity"

  let(:partner)    { create(:partner, :supplier, name: "Acme Ltd", iban: nil) }
  let(:owner)      { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)  { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:iban)       { "BE68539007547034" }

  def register_by(user, iban: self.iban, partner: self.partner) = Payments::RegisterBankAccount.call(partner: partner, iban: iban, holder_name: "Acme Ltd", user: user)[:account]

  before do
    owner
    accountant
    assistant
    sign_in accountant
  end

  describe "the flag and the right" do
    it "is closed when the feature is off" do
      entity.update!(features: entity.features.merge("b01b" => false))

      get accounting_partner_bank_accounts_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "is for those who may read records: a reader sees the list, masked" do
      register_by(assistant)
      sign_in reader

      get accounting_partner_bank_accounts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("BE68 **** **** 7034")
      expect(response.body).not_to include(iban)
    end
  end

  describe "the list" do
    it "separates what waits for verification, what is in use, and what is over" do
      waiting = register_by(assistant)
      in_use  = register_by(assistant, iban: "FR1420041010050500013M02606", partner: create(:partner, :supplier, name: "Beta SA", iban: nil)).tap { |a| Payments::VerifyBankAccount.call(account: a, user: accountant, method: :phone_callback) }
      blocked = register_by(assistant, iban: "NL91ABNA0417164300", partner: create(:partner, :supplier, name: "Gamma BV", iban: nil)).tap { |a| Payments::BlockBankAccount.call(account: a, user: accountant, reason: "Returned") }

      get accounting_partner_bank_accounts_path

      body = response.body
      expect(body).to include("To verify", "In use", "Blocked or replaced")
      expect(body.index("Acme Ltd")).to be < body.index("Beta SA")
      expect([ waiting, in_use, blocked ].map(&:masked_iban)).to all(satisfy { |masked| body.include?(masked) })
      expect(body).to include("Returned")
    end

    it "offers the IBANs written on the suppliers' records that were never registered, for a person to register" do
      partner.update_columns(iban: iban)

      get accounting_partner_bank_accounts_path

      expect(response.body).to include("To register").and include("Acme Ltd")
      expect(response.body).not_to include(iban)
    end

    it "says so when there is nothing" do
      get accounting_partner_bank_accounts_path

      expect(response.body).to include("No bank account yet")
    end
  end

  describe "registering" do
    it "is a person's act: the account is unverified and observed" do
      get new_accounting_partner_bank_account_path
      expect(response).to have_http_status(:ok)

      post accounting_partner_bank_accounts_path, params: { partner_bank_account: { partner_id: partner.id, iban: "be68 5390 0754 7034", holder_name: "Acme Ltd", bic: "GKCCBEBB" } }

      account = Accounting::PartnerBankAccount.sole
      expect(response).to redirect_to(accounting_partner_bank_account_path(account))
      expect(account).to have_attributes(iban: iban, status: "unverified", created_by: accountant, source: "manual", bic: "GKCCBEBB")
    end

    it "tells why when the IBAN is not valid, and keeps what was typed" do
      post accounting_partner_bank_accounts_path, params: { partner_bank_account: { partner_id: partner.id, iban: "BE68539007547035", holder_name: "Acme Ltd" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("not valid").and include("Acme Ltd")
      expect(Accounting::PartnerBankAccount.count).to eq(0)
    end

    it "registers, on one click, the IBAN written on a supplier's record" do
      partner.update_columns(iban: iban)

      post register_from_partner_accounting_partner_bank_accounts_path, params: { partner_id: partner.id }

      expect(Accounting::PartnerBankAccount.sole).to have_attributes(partner: partner, iban: iban, holder_name: "Acme Ltd", status: "unverified", source: "manual")
    end

    it "is refused to a reader" do
      sign_in reader

      post accounting_partner_bank_accounts_path, params: { partner_bank_account: { partner_id: partner.id, iban: iban, holder_name: "Acme Ltd" } }

      expect(Accounting::PartnerBankAccount.count).to eq(0)
    end
  end

  describe "one account" do
    let!(:account) { register_by(assistant) }

    it "shows the full IBAN to those who verify, and says how to verify safely" do
      get accounting_partner_bank_account_path(account)

      expect(response.body).to include("BE68 5390 0754 7034") # in groups of four, as a person reads it out on the phone
      expect(response.body).to include("a number you already had")
      expect(response.body).to include("Alice Accountant").or include("Anna Assistant")
    end

    it "shows the full IBAN to nobody else" do
      sign_in assistant

      get accounting_partner_bank_account_path(account)

      expect(response.body).to include("BE68 **** **** 7034")
      expect(response.body).not_to include(iban)
      expect(response.body).not_to include("BE68 5390 0754 7034")
    end

    it "is verified by another person, with how it was verified" do
      post verify_accounting_partner_bank_account_path(account), params: { method: "phone_callback", note: "Called the number of the contract" }

      expect(response).to redirect_to(accounting_partner_bank_account_path(account))
      expect(account.reload).to have_attributes(status: "verified", verified_by: accountant, verification_method: "phone_callback")
    end

    it "is not verified by the person who registered it, and says why" do
      own = register_by(accountant, iban: "FR1420041010050500013M02606", partner: create(:partner, :supplier, name: "Own SA", iban: nil))

      post verify_accounting_partner_bank_account_path(own), params: { method: "phone_callback" }

      expect(flash[:alert]).to match(/someone else/i)
      expect(own.reload).to be_unverified
    end

    it "is not verified without saying how" do
      post verify_accounting_partner_bank_account_path(account), params: { method: "" }

      expect(flash[:alert]).to match(/how the account was verified/i)
      expect(account.reload).to be_unverified
    end

    it "is not verified by an assistant" do
      sign_in assistant

      post verify_accounting_partner_bank_account_path(account), params: { method: "phone_callback" }

      expect(account.reload).to be_unverified
    end

    it "is blocked with a reason" do
      post block_accounting_partner_bank_account_path(account), params: { reason: "Supplier warned of a fraud" }

      expect(account.reload).to have_attributes(status: "blocked", blocked_reason: "Supplier warned of a fraud")
    end

    it "tells its history: who registered, who verified, when, and nothing of the full IBAN" do
      Payments::VerifyBankAccount.call(account: account, user: accountant, method: :supplier_statement, note: "Statement of 3 October")

      get accounting_partner_bank_account_path(account)

      body = response.body
      expect(body).to include("registered", "verified")
      expect(body).to include("Supplier statement").and include("Statement of 3 October")
    end

    it "does not show an account of another company" do
      other = ActsAsTenant.with_tenant(create(:entity)) { create(:partner_bank_account) }

      get accounting_partner_bank_account_path(other)

      expect(response).to have_http_status(:not_found).or redirect_to(accounting_root_path)
    end
  end

  describe "from an invoice" do
    let(:fiscal_year) { create(:fiscal_year, status: :open) }
    let(:invoice) { create(:invoice, :supplier, partner: partner, fiscal_year: fiscal_year, iban: iban) }

    it "offers to register the IBAN the invoice carries, until it is registered" do
      get accounting_invoice_path(invoice)
      expect(response.body).to include("Register this IBAN")

      post register_iban_accounting_invoice_path(invoice)

      expect(Accounting::PartnerBankAccount.sole).to have_attributes(partner: partner, iban: iban, source: "invoice", created_by: accountant, status: "unverified")
      follow_redirect!
      expect(response.body).not_to include("Register this IBAN")
    end

    it "offers nothing on an invoice without an IBAN" do
      invoice.update!(iban: nil)

      get accounting_invoice_path(invoice)

      expect(response.body).not_to include("Register this IBAN")
    end
  end

  describe "the notifications" do
    it "open the account a change is about, and the invoice an IBAN differs on" do
      account = register_by(assistant)
      change = Accounting::Notify.call(user: accountant, event: "bank_account_changed:#{account.id}", subject: account)
      invoice = create(:invoice, :supplier, partner: partner, fiscal_year: create(:fiscal_year, status: :open))
      mismatch = Accounting::Notify.call(user: accountant, event: "bank_account_invoice_mismatch:#{invoice.id}", subject: invoice)

      get accounting_notifications_path
      expect(response.body).to include("bank account was changed").and include("IBAN of an invoice")

      post read_accounting_notification_path(change)
      expect(response).to redirect_to(accounting_partner_bank_account_path(account))
      post read_accounting_notification_path(mismatch)
      expect(response).to redirect_to(accounting_invoice_path(invoice))
    end
  end

  describe "the observation period" do
    it "is the owner's to set, in hours, and is recorded" do
      sign_in owner

      patch accounting_settings_entity_path, params: { entity: { iban_cooling_hours: "12" } }

      expect(entity.reload.iban_cooling_hours).to eq(12)
      log = Accounting::AuditLog.for_record(entity).for_action("payment_option_changed").sole
      expect(log.payload).to include("option" => "iban_cooling_hours", "from" => 24, "to" => 12)
      expect(log.user_id).to eq(owner.id)
    end

    it "is not an accountant's to change" do
      patch accounting_settings_entity_path, params: { entity: { iban_cooling_hours: "0" } }

      expect(entity.reload.iban_cooling_hours).to eq(24)
    end

    it "is a whole number of hours, at most a month" do
      sign_in owner

      [ "-1", "721", "abc" ].each do |bad|
        patch accounting_settings_entity_path, params: { entity: { iban_cooling_hours: bad } }
        expect(entity.reload.iban_cooling_hours).to eq(24), bad
      end
    end
  end

  describe "the journals" do
    it "never write an IBAN of a form or of the API: it is filtered in the request log" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      filtered = filter.filter("partner_bank_account" => { "iban" => iban }, "partner" => { "iban" => iban }, "iban" => iban)

      expect(filtered.to_json).not_to include(iban)
    end
  end
end

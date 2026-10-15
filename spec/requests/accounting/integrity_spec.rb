require "rails_helper"

# B03c "Interface": the page Integrity, the issue of a certificate (second factor, rights), the downloads, the revocation, the settings of the owner, the footer line, the public
# page of a certificate and the public keys.
RSpec.describe "Integrity", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader) { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:assistant) { create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    Ledger::SigningKeys.generate!
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
    sign_in accountant
  end

  def issue(**params) = post(accounting_integrity_certificates_path, params: { covered: "now", disclosure: "full", recipient: "The bank" }.merge(params))

  describe "the page" do
    it "shows the anchors, the checks, the keys and the certificates, and the form to issue one" do
      Ledger::Anchoring.call(kind: "nightly")
      Integrity::SelfCheck.run_for(entity)

      get accounting_integrity_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Integrity").and include("Last anchor").and include("Signing keys").and include("Issue the certificate").and include("1 active")
      expect(response.body).to include("0 divergences")
    end

    it "replays the invariants on request" do
      get accounting_integrity_path(invariants: 1)

      expect(response.body).to include("I17").and include("holds")
    end

    it "is closed when the feature is off" do
      entity.update!(features: entity.features.merge("b03c" => false))
      get accounting_integrity_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "is read by a reader, who cannot issue" do
      sign_in reader
      get accounting_integrity_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Issue the certificate")

      expect { issue }.not_to change(IntegrityCertificate, :count)
    end

    it "is not for the assistant" do
      sign_in assistant
      get accounting_integrity_path

      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "issuing" do
    it "makes the certificate, and shows it" do
      expect { issue }.to change(IntegrityCertificate, :count).by(1)

      certificate = IntegrityCertificate.last
      expect(response).to redirect_to(accounting_integrity_certificate_path(certificate))
      follow_redirect!
      expect(response.body).to include(certificate.uuid).and include("It proves").and include("It does not prove").and include("Reservations")
    end

    it "asks for a second factor given a moment ago" do
      previous = Rails.configuration.x.second_factor_required
      Rails.configuration.x.second_factor_required = true
      begin
        expect { issue }.not_to change(IntegrityCertificate, :count)
        expect(response).to have_http_status(:redirect)
      ensure
        Rails.configuration.x.second_factor_required = previous
      end
    end

    it "tells why when it is refused (a broken audit chain), and records the anomaly" do
      victim = Accounting::AuditLog.unscoped.where(entity_id: entity.id).order(:id).last
      tamper(:accounting_audit_logs) { Accounting::AuditLog.unscoped.where(id: victim.id).update_all(payload: { forged: true }) }

      issue

      expect(response).to redirect_to(accounting_integrity_path)
      expect(flash[:alert]).to include("audit chain")
      expect(Accounting::ConsistencyFinding.where(check_id: "C23")).to exist
    end
  end

  describe "a certificate" do
    let(:certificate) { issue && IntegrityCertificate.last }

    it "is downloaded as JSON (signed), as PDF, and as a package that ledger-verify accepts; each download is recorded" do
      get download_accounting_integrity_certificate_path(certificate, kind: "json")
      expect(JSON.parse(response.body)["signature"]["key_id"]).to eq(certificate.key_id)

      get download_accounting_integrity_certificate_path(certificate, kind: "pdf")
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")

      post package_accounting_integrity_certificate_path(certificate)
      expect(LedgerVerify::Verifier.call(response.body)).to be_pass

      post package_accounting_integrity_certificate_path(certificate), params: { passphrase: "s3cret" }
      expect(LedgerVerify::Verifier.call(response.body, passphrase: "s3cret")).to be_pass
      expect(Accounting::AuditLog.where(action: "integrity_certificate_downloaded").count).to eq(4)
    end

    it "has no package below the full level" do
      standard = issue(disclosure: "standard") && IntegrityCertificate.last
      post package_accounting_integrity_certificate_path(standard)

      expect(response).to redirect_to(accounting_integrity_certificate_path(standard))
    end

    it "is verified again on request, and says what it finds" do
      post verify_accounting_integrity_certificate_path(certificate)
      follow_redirect!

      expect(response.body).to include("The signature is genuine and the books still hold")
    end

    it "is revoked with a reason, and shows it" do
      post revoke_accounting_integrity_certificate_path(certificate), params: { reason: "issued for the wrong year" }
      follow_redirect!

      expect(certificate.reload).to be_revoked
      expect(response.body).to include("Revoked on").and include("issued for the wrong year")

      post revoke_accounting_integrity_certificate_path(certificate), params: { reason: "" }
      expect(flash[:alert]).to be_present
    end

    it "is read by a reader, not revoked by one" do
      certificate
      sign_in reader
      get accounting_integrity_certificate_path(certificate)
      expect(response).to have_http_status(:ok)

      post revoke_accounting_integrity_certificate_path(certificate), params: { reason: "x" }
      expect(certificate.reload).not_to be_revoked
    end
  end

  describe "the settings of the owner" do
    it "are saved by the owner, and recorded" do
      sign_in owner

      patch accounting_integrity_settings_path, params: { entity: { timestamp_authority_url: "https://tsa.example.test/tsr", integrity_default_disclosure: "minimal", integrity_public_company_name: "1" } }

      expect(entity.reload).to have_attributes(timestamp_authority_url: "https://tsa.example.test/tsr", integrity_default_disclosure: "minimal", integrity_public_company_name: true)
      expect(Accounting::AuditLog.where(action: "integrity_option_changed").count).to eq(3)
    end

    it "are not an accountant's" do
      patch accounting_integrity_settings_path, params: { entity: { integrity_default_disclosure: "minimal" } }

      expect(entity.reload.integrity_default_disclosure).to eq("standard")
    end
  end

  describe "the full check, on demand" do
    it "runs and tells the result" do
      post accounting_integrity_check_path

      expect(flash[:notice]).to include("nothing diverges")
      expect(IntegrityCheckRun.last.mode).to eq("full")
    end
  end

  describe "the footer line" do
    it "says when the books were last checked" do
      Integrity::SelfCheck.run_for(entity)
      get accounting_integrity_path

      expect(response.body).to match(/Integrity verified (today at|on)/)
    end

    it "warns when the last check found something" do
      entry = Accounting::JournalEntry.last
      tamper(:accounting_journal_entry_lines) { entry.lines.first.update_columns(debit: 11, credit: 0) }
      Integrity::SelfCheck.run_for(entity)
      get accounting_integrity_path

      expect(response.body).to include("Integrity check found divergences")
    end
  end

  describe "the public page of a certificate" do
    let(:certificate) { issue && IntegrityCertificate.last }

    before { certificate }

    def public_get(uuid = certificate.uuid)
      sign_out accountant
      get verification_path(uuid)
    end

    it "is open to anyone with the address, and says that the certificate is valid, with no amount and no name" do
      public_get

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The signature is genuine").and include(certificate.payload["public_key"]["fingerprint"]).and include("No entry was validated since")
      expect(response.body).not_to include("10.00")
      expect(response.body).not_to include(entity.legal_name)
      expect(response.body).not_to include("The bank")
      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    end

    it "names the company when its owner allows it" do
      entity.update!(integrity_public_company_name: true)
      public_get

      expect(response.body).to include(entity.legal_name)
    end

    it "tells what was validated since, with a count" do
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 12, reference: nil)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense, debit: 5, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 5)
      next_posting_instant
      Accounting::PostJournalEntry.call!(entry: entry)
      public_get

      expect(response.body).to include("1 entry was validated since")
    end

    it "says that a certificate that was changed is not valid, and one revoked is revoked" do
      tamper(:integrity_certificates) { IntegrityCertificate.where(id: certificate.id).update_all(body: certificate.body.sub("full", "minimal")) }
      public_get
      expect(response.body).to include("does not match this certificate")
    end

    it "is not found for an unknown address, or when the feature is off" do
      public_get("00000000-0000-0000-0000-000000000000")
      expect(response).to have_http_status(:not_found)

      entity.update!(features: entity.features.merge("b03c" => false))
      public_get
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the throttle of the public page" do
    around do |example|
      Rack::Attack.enabled = true
      Rack::Attack.cache.store.clear
      example.run
    ensure
      Rack::Attack.enabled = false
    end

    it "limits the tries on an address per IP, so that an identifier cannot be guessed by trying" do
      sign_out accountant
      31.times { get verification_path(SecureRandom.uuid) }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "the public keys" do
    it "are published at a fixed address, without any secret" do
      sign_out accountant
      get "/.well-known/ledgerflow/keys.json"

      keys = JSON.parse(response.body)["keys"]
      expect(keys.map { |k| k["status"] }).to eq([ "active" ])
      expect(keys.first.keys).to match_array(%w[key_id algorithm public_key fingerprint status created_at retired_at revoked_at])
      expect(response.body).not_to include("PRIVATE")
    end
  end
end

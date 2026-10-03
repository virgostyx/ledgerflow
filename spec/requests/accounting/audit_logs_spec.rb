require "rails_helper"

RSpec.describe "Accounting::AuditLogs", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager, user: manager, entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor, user: auditor, entity: entity) }

  before { sign_in accountant }

  def rows(action, record) = Accounting::AuditLog.where(auditable_type: record.class.name, auditable_id: record.id, action: action)

  describe "what is logged (one row per action)" do
    let!(:account) { create(:account) }

    it "logs the creation, each update and the destruction of an account, with before/after" do
      expect(rows("create", account).count).to eq(1)

      account.update!(label_fr: "Renamed")
      log = rows("update", account).sole
      expect(log.payload["changes"]["label_fr"]).to eq([ account.label_fr_before_last_save, "Renamed" ])

      account.destroy!
      expect(rows("destroy", account).count).to eq(1)
    end

    it "does not log a save that changes nothing" do
      expect { account.save! }.not_to change(Accounting::AuditLog, :count)
    end

    it "logs posting once (post_entry) and not as an extra update; a reversal once (reverse_entry)" do
      entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)
      expect(rows("create", entry).count).to eq(1)

      Accounting::PostJournalEntry.call(entry: entry)
      expect(rows("post_entry", entry).count).to eq(1)
      expect(rows("update", entry).where("payload::text ILIKE '%\"status\"%'").count).to eq(0)

      Accounting::ReverseJournalEntry.call(entry: entry.reload, reason: "Booked twice")
      expect(rows("reverse_entry", entry).count).to eq(1)
    end

    it "logs the lines of an entry" do
      entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)
      entry.lines.each { |line| expect(rows("create", line).count).to eq(1) }
    end
  end

  describe "GET /accounting/audit_logs" do
    it "lists entries with the chain status and honours the filters" do
      account = create(:account)
      account.update!(label_fr: "Renamed")
      get accounting_audit_logs_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Audit trail", "Chain intact on")

      get accounting_audit_logs_path(action_name: "update", auditable_type: "Accounting::Account", q: "Renamed")
      expect(response.body).to include("label_fr")
      get accounting_audit_logs_path(action_name: "update", q: "nothing-like-this")
      expect(response.body).to include("No entry matches.")
    end

    it "filters by entry reference and by reason" do
      entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)
      Accounting::PostJournalEntry.call(entry: entry)
      Accounting::ReverseJournalEntry.call(entry: entry.reload, reason: "Booked twice")
      get accounting_audit_logs_path(reference: entry.reference, with_reason: "1")
      expect(response.body).to include("reverse_entry", "Booked twice")
    end

    it "shows a broken chain with the exact entry" do
      create(:account)
      victim = Accounting::AuditLog.where(entity_id: entity.id).last
      ApplicationRecord.connection.execute("ALTER TABLE accounting_audit_logs DISABLE TRIGGER enforce_audit_log_immutability")
      Accounting::AuditLog.where(id: victim.id).update_all(action: "tampered")
      ApplicationRecord.connection.execute("ALTER TABLE accounting_audit_logs ENABLE TRIGGER enforce_audit_log_immutability")
      get accounting_audit_logs_path
      expect(response.body).to include("Chain broken at entry ##{victim.id}")
    end

    it "is open to the external auditor, and closed to the reader (F01 capability table)" do
      sign_in auditor
      get accounting_audit_logs_path
      expect(response).to have_http_status(:ok)

      sign_out auditor
      sign_in manager
      get accounting_audit_logs_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /accounting/audit_logs/:id — the before/after viewer" do
    it "reproduces the recorded values field by field" do
      account = create(:account, label_fr: "Original")
      account.update!(label_fr: "Renamed")
      log = rows("update", account).sole
      get accounting_audit_log_path(log)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="audit-diff"', "label_fr", CGI.escapeHTML('"Original"'), CGI.escapeHTML('"Renamed"'), log.content_hash)
    end

    it "shows the raw payload for an entry without field changes" do
      log = Accounting::AuditLog.record!(auditable: create(:account), action: "custom", payload: { note: "hello" })
      get accounting_audit_log_path(log)
      expect(response.body).to include("Payload", "hello")
    end
  end

  it "records who acted, from where, during a request" do
    account = create(:account)
    patch accounting_settings_account_path(account), params: { accounting_account: { label_fr: "Via the app" } }
    log = rows("update", account).last
    expect(log).to have_attributes(user_id: accountant.id, user_email: accountant.email)
    expect(log.ip_address).to be_present
    expect(log.request_id).to be_present
  end

  describe "another entity's trail never shows" do
    let(:other) { create(:entity) }
    let!(:foreign) do
      ActsAsTenant.with_tenant(other) do
        Accounting::AuditLog.record!(auditable: create(:partner), action: "foreign_action", user: create(:user, email: "stranger@elsewhere.example"), reason: "foreign reason")
      end
    end

    it "keeps its rows out of the list, whatever the filters" do
      get accounting_audit_logs_path

      expect(response.body).not_to include("foreign_action", "stranger@elsewhere.example", "foreign reason")
    end

    it "keeps its actions, types and users out of the filter menus" do
      options = Accounting::AuditLogsQuery.filter_options

      expect(options[:actions]).not_to include("foreign_action")
      expect(options[:users].map(&:first)).not_to include("stranger@elsewhere.example")
    end

    it "answers 404 for a row of another entity opened by its id" do
      get accounting_audit_log_path(foreign)

      expect(response).to have_http_status(:not_found)
    end

    it "does not count them in the chain" do
      expect(Accounting::AuditLog.where(action: "foreign_action")).to be_empty
    end
  end
end

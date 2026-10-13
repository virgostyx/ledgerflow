require "rails_helper"

# B01 absolute rule: LedgerFlow keeps no bank login of the user, calls no payment API and initiates no payment. It prepares a file the person authorizes in their bank.
# These checks watch the schema and the traces, so that it stays true as the code grows.
RSpec.describe "No bank credentials, no initiated payment, no IBAN in the clear" do
  describe "the schema" do
    CREDENTIAL = /login|passw|passcode|\bpin\b|_pin\b|credential|digipass|card_?reader|secret|api_?key|access_?token|refresh_?token|oauth/i
    BANKISH_TABLE = /bank|payment|iban|sepa|coda/i
    # What is not a bank credential: our own users' sign-in, a client's webhook signature, the Peppol access point, passkeys, API keys of LedgerFlow's own API.
    ALLOWED = %w[users webhook_subscriptions entities webauthn_credentials api_clients api_keys].freeze

    def columns_of(tables) = tables.flat_map { |t| ApplicationRecord.connection.columns(t).map { |c| [ t, c.name ] } }

    it "has no column that looks like a credential in any table about banks, payments or statements" do
      tables = ApplicationRecord.connection.tables.grep(BANKISH_TABLE) - ALLOWED
      offenders = columns_of(tables).select { |_, column| column.match?(CREDENTIAL) }

      expect(offenders).to be_empty, "credential-like columns: #{offenders.inspect}"
    end

    it "has no column named after a bank login anywhere (the credentials of LedgerFlow's own users excepted)" do
      tables = ApplicationRecord.connection.tables - ALLOWED
      offenders = columns_of(tables).select { |_, column| column.match?(/bank.*(login|passw|secret|credential|token)|(login|passw|credential).*bank/i) }

      expect(offenders).to be_empty, "bank credentials: #{offenders.inspect}"
    end

    it "has the IBANs of the payments encrypted: the database holds no IBAN in the clear" do
      %w[partner_bank_accounts payment_items accounting_invoices].each do |table|
        raw = ApplicationRecord.connection.select_values("SELECT iban FROM #{table} WHERE iban IS NOT NULL")
        expect(raw.grep(/\A[A-Z]{2}\d{2}[A-Z0-9]{10,30}\z/)).to be_empty, "#{table}.iban holds a clear IBAN"
      end
    end
  end

  describe "the code" do
    it "calls no payment initiation, no open-banking and no bank API from the payment code" do
      code = Dir["app/services/payments/**/*.rb", "app/controllers/accounting/payments_controller.rb", "app/models/payments/**/*.rb"].map { |f| File.read(f) }.join("\n")

      expect(code).not_to match(/Net::HTTP|Faraday|HTTParty|RestClient|URI\.open|open-uri|PSD2|PISP|AISP|Berlin Group|STET/i)
    end
  end

  describe "the traces", type: :request do
    include_context "with approvable batch"

    let(:iban) { "BE68539007547034" }
    let(:log_path) { Rails.root.join("log/test.log") }

    it "never write an IBAN in full: not in the log, the audit trail, the report, the notifications" do
      owner
      start = File.size?(log_path).to_i
      sign_in preparer

      batch = approved_batch(posted)
      sign_in authorizer
      post export_accounting_payment_path(batch)
      get accounting_payment_path(batch)
      get accounting_payments_path
      Payments::Preflight.call(batch.reload)
      typed = "FR1420041010050500013M02606" # an IBAN typed in a form: the log must filter it
      other = create(:partner, :supplier, name: "Beta SA", iban: nil)
      post accounting_partner_bank_accounts_path, params: { partner_bank_account: { partner_id: other.id, iban: typed, holder_name: "Beta SA" } }
      Accounting::Notify.call(user: owner, event: "bank_account_changed:#{account.id}", subject: account)

      new_log = File.open(log_path) { |f| f.seek(start); f.read.to_s }
      expect(new_log).not_to include(iban)
      expect(new_log).not_to include(typed)
      expect(Accounting::PartnerBankAccount.find_by(partner: other)).to be_present, "the form was not posted"
      expect(Accounting::AuditLog.pluck(:payload, :reason).flatten.compact.to_json).not_to include(iban)
      expect(batch.reload.preflight_report.to_json).not_to include(iban)
      expect(Accounting::Notification.pluck(:data).to_json).not_to include(iban) if Accounting::Notification.column_names.include?("data")
    end
  end
end

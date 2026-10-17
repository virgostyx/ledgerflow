require "rails_helper"

# B03c: issuing a certificate (critères 6, 7, 8, 10): what it says, what it proves and does not, how it is signed, when it is refused (the audit chain, the anchors, I1, I2), what
# is only a reservation, and what each level of disclosure gives.
RSpec.describe Integrity::IssueCertificate do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    Ledger::SigningKeys.generate!
  end

  def post_entry(amount = 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    Current.set(user: user) { Accounting::PostJournalEntry.call!(entry: entry) }
    entry.reload
  end

  def issue(**opts) = described_class.call(user: user, recent_second_factor: true, **opts)

  def payload(certificate) = JSON.parse(certificate.body)

  describe "a certificate for now" do
    it "makes an anchor for the instant, and says what it covers: the range of anchors, the entries, the lines, the totals" do
      post_entry(10)
      post_entry(25)

      result = issue(disclosure: "standard", recipient: "The bank")
      certificate = result[:certificate]
      body = payload(certificate)

      expect(result).to be_success
      expect(Ledger::Anchor.count).to eq(1)
      expect(Ledger::Anchor.last.kind).to eq("on_demand")
      expect(body).to include("type" => "ledgerflow-integrity-certificate", "version" => 1, "id" => certificate.uuid, "disclosure" => "standard", "recipient" => "The bank")
      expect(body["coverage"]).to include("through_seq" => 2, "entries" => 2, "lines" => 4, "anchors" => include("from" => 1, "to" => 1, "last_anchor_hash" => Ledger::Anchor.last.anchor_hash))
      expect(body["totals"]).to include("debit" => "35.00", "credit" => "35.00")
      expect(body["totals"]["by_class"]).to include("6" => { "debit" => "35.00", "credit" => "0.00" }, "4" => { "debit" => "0.00", "credit" => "35.00" })
      expect(certificate).to have_attributes(through_seq: 2, anchor_number: 1, covered_at: Ledger::Anchor.last.anchored_at)
    end

    it "is signed (Ed25519) over its canonical JSON, with the public key and its fingerprint in it, and the signature verifies" do
      post_entry
      certificate = issue(disclosure: "standard")[:certificate]
      body = payload(certificate)
      key = Ledger::SigningKey.find_by!(key_id: certificate.key_id)

      expect(body["public_key"]).to eq("key_id" => key.key_id, "algorithm" => "Ed25519", "public_key" => key.public_key, "fingerprint" => key.fingerprint)
      expect(LedgerVerify::Canonical.generate(JSON.parse(certificate.body))).to eq(certificate.body) # stored as it was signed
      expect(Ledger::SigningKeys.verify(certificate.key_id, certificate.body, certificate.signature)).to be(true)
      expect(Ledger::SigningKeys.verify(certificate.key_id, certificate.body.sub("10.00", "11.00"), certificate.signature)).to be(false)
    end

    it "carries, in clear, the table of what it proves and what it does not, and the address to verify it" do
      post_entry
      body = payload(issue(disclosure: "standard")[:certificate])

      expect(body["proves"].join(" ")).to include("fingerprint").and include("audit trail")
      expect(body["does_not_prove"].join(" ")).to include("accurate").and include("supporting documents").and include("audit opinion")
      expect(body["verification_path"]).to eq("/verify/#{body['id']}")
    end

    it "tells that there is no external timestamp, and that the proof rests on the key of the instance alone" do
      post_entry
      body = payload(issue(disclosure: "standard")[:certificate])

      expect(body["timestamp"]).to include("status" => "none")
      expect(body["reservations"].join(" ")).to include("external timestamp")
    end

    it "gives the result of the invariants that can be replayed, the audit chain, the documents, the locked periods, the anomalies, the witnesses, the software" do
      post_entry
      body = payload(issue(disclosure: "standard")[:certificate])

      expect(body["invariants"]).to include("I1" => include("status" => "holds"), "I2" => include("status" => "holds"), "I17" => include("status" => "holds"))
      expect(body["invariants"]["I3"]["status"]).to eq("not_replayed")
      expect(body["audit_chain"]).to include("intact" => true, "length" => be_positive, "version_1_events" => 0, "unchained_events" => 0)
      expect(body).to include("blocking_anomalies" => 0, "documents" => include("mismatch" => 0, "missing" => 0), "locked_periods" => [], "witnesses" => include("divergences" => 0))
      expect(body["software"]).to include("revision" => be_present, "manifest_hash" => match(/\A\h{64}\z/))
    end
  end

  describe "with a timestamp authority" do
    include_context "with a timestamp authority"

    before { entity.update!(timestamp_authority_url: "https://tsa.example.test/tsr", timestamp_authority_ca: authority.ca_pem) }

    it "timestamps the anchor it makes, and says so, without the reservation about the missing timestamp" do
      post_entry
      allow(Ledger::Timestamping).to receive(:default_transport).and_return(authority.transport)

      body = payload(issue(disclosure: "standard")[:certificate])

      expect(body["timestamp"]).to include("status" => "granted", "authority" => "https://tsa.example.test/tsr", "anchors" => 1, "anchors_timestamped" => 1)
      expect(body["reservations"].join(" ")).not_to include("No external timestamp")
    end

    it "is issued all the same when the authority does not answer, and says that the timestamp is pending" do
      post_entry
      allow(Ledger::Timestamping).to receive(:default_transport).and_return(authority.transport(unavailable: true))

      result = issue(disclosure: "standard")
      body = payload(result[:certificate])

      expect(result).to be_success
      expect(body["timestamp"]).to include("status" => "pending")
      expect(body["reservations"].join(" ")).to include("was not obtained yet")
    end
  end

  describe "an instant of the past: the bound of an anchor" do
    it "covers the books as they were at that anchor, not after" do
      post_entry(10)
      first = Ledger::Anchoring.call(kind: "nightly")
      post_entry(500)

      certificate = issue(disclosure: "standard", anchor_number: first.number)[:certificate]

      expect(payload(certificate)["coverage"]).to include("through_seq" => 1, "entries" => 1)
      expect(payload(certificate)["totals"]["debit"]).to eq("10.00")
      expect(certificate.covered_at).to eq(first.anchored_at)
    end

    it "refuses an anchor that does not exist, and an instant that is not an anchor" do
      post_entry

      expect(issue(disclosure: "standard", anchor_number: 42)).to be_failure
    end
  end

  describe "the levels of disclosure" do
    before { post_entry(10) }

    it "minimal: fingerprints, ranges and results of the invariants, no amount" do
      body = payload(issue(disclosure: "minimal")[:certificate])

      expect(body).not_to have_key("totals")
      expect(body["coverage"].keys).not_to include("lines")
      expect(body.to_json).not_to include("10.00")
      expect(body["coverage"]).to include("entries" => 1, "through_seq" => 1)
    end

    it "standard: in addition the totals and a summary by class of accounts" do
      expect(payload(issue(disclosure: "standard")[:certificate])["totals"].keys).to match_array(%w[debit credit by_class])
    end

    it "full: as standard, and says the verification package exists" do
      body = payload(issue(disclosure: "full")[:certificate])

      expect(body["totals"]).to be_present
      expect(body["package"]).to include("included" => true)
    end

    it "refuses a level that does not exist" do
      expect(issue(disclosure: "everything")).to be_failure
    end
  end

  describe "the conditions" do
    before { post_entry }

    it "needs a second factor given recently" do
      result = described_class.call(user: user, recent_second_factor: false, disclosure: "standard")

      expect(result).to be_failure
      expect(result.message).to match(/second factor/i)
      expect(IntegrityCertificate.count).to eq(0)
    end

    it "needs an active signing key" do
      Ledger::SigningKey.update_all(status: "retired")

      expect(issue(disclosure: "standard")).to be_failure
    end

    it "is refused when the audit chain is broken, and creates the blocking anomaly" do
      victim = Accounting::AuditLog.unscoped.where(entity_id: entity.id).order(:id).last
      tamper(:accounting_audit_logs) { Accounting::AuditLog.unscoped.where(id: victim.id).update_all(payload: { forged: true }) }

      result = issue(disclosure: "standard")

      expect(result).to be_failure
      expect(result.message).to include("audit")
      expect(Accounting::ConsistencyFinding.where(check_id: "C23")).to exist
      expect(IntegrityCertificate.count).to eq(0)
    end

    it "is refused when the chain of anchors is broken" do
      Ledger::Anchoring.call(kind: "nightly")
      post_entry
      Ledger::Anchoring.call(kind: "nightly")
      tamper(:ledger_anchors) { Ledger::Anchor.where(number: 1).update_all(merkle_root: "e" * 64) }

      result = issue(disclosure: "standard")

      expect(result).to be_failure
      expect(result.message).to include("anchor")
      expect(Accounting::ConsistencyFinding.where(check_id: "C23")).to exist
    end

    it "is refused when I2 does not hold (the debits are not the credits)" do
      line = Accounting::JournalEntryLine.joins(:journal_entry).merge(Accounting::JournalEntry.in_ledger).first
      tamper(:accounting_journal_entry_lines) { line.update_columns(debit: line.debit + 1) }

      result = issue(disclosure: "standard")

      expect(result).to be_failure
      expect(result.message).to include("I2")
    end

    it "only reserves the other failures: a document that does not match, an open blocking anomaly, a version 1 audit chain" do
      document = create(:document)
      document.update_columns(integrity_status: "mismatch")
      Accounting::ConsistencyRun.create!(trigger: "spec", started_at: Time.current).findings.create!(entity: entity, check_id: "C04", severity: "blocking", fingerprint: "fp1", message: "x", subject_type: "Accounting::Account", subject_id: payable.id)

      result = issue(disclosure: "standard")
      body = payload(result[:certificate])

      expect(result).to be_success
      expect(body["reservations"].join(" ")).to include("document").and include("blocking")
      expect(body["documents"]["mismatch"]).to eq(1)
    end

    it "says that it covers the retroactive anchor, when it does" do
      entry = Accounting::JournalEntry.last
      tamper(:accounting_journal_entries) { Accounting::JournalEntry.where(id: entry.id).update_all(content_hash: nil, content_hash_source: nil) }
      Ledger::Anchoring.call(kind: "retroactive")

      body = payload(issue(disclosure: "standard")[:certificate])

      expect(body["retroactive"]).to eq("covers" => true, "entries" => 1)
      expect(body["reservations"].join(" ")).to include("before the anchoring began")
    end
  end

  describe "the certificate once issued" do
    it "is written in the audit trail, and cannot be changed or deleted, but can be revoked with a reason" do
      post_entry
      certificate = issue(disclosure: "standard")[:certificate]

      expect(Accounting::AuditLog.where(action: "integrity_certificate_issued", auditable_id: certificate.id)).to exist
      expect { ApplicationRecord.transaction(requires_new: true) { certificate.update_columns(body: "{}") } }.to raise_error(ActiveRecord::StatementInvalid, /cannot be changed/)
      expect { ApplicationRecord.transaction(requires_new: true) { certificate.delete } }.to raise_error(ActiveRecord::StatementInvalid, /cannot be deleted/)

      expect(Integrity::RevokeCertificate.call(certificate: certificate, user: user, reason: "issued for the wrong year")).to be_success
      expect(certificate.reload).to have_attributes(revocation_reason: "issued for the wrong year", revoked_at: be_present)
      expect(Integrity::RevokeCertificate.call(certificate: certificate, user: user, reason: "again")).to be_failure
      expect(Integrity::RevokeCertificate.call(certificate: certificate, user: user, reason: "")).to be_failure
    end
  end
end

require "rails_helper"

RSpec.describe "Audit trail integrity chain (R18)", type: :model do
  include_context "with entity"

  let!(:account) { create(:account) } # creating it is itself audited

  def log(action = "test", **attrs) = Accounting::AuditLog.record!(auditable: account, action: action, **attrs)

  after { Current.reset }

  it "chains each entry to the previous one: hash = SHA-256(previous hash + content)" do
    creation = Accounting::AuditLog.where(auditable_id: account.id).last
    first = log("a")
    second = log("b", payload: { amount: "10.00" })
    expect(creation.previous_hash).to be_nil
    expect(first.previous_hash).to eq(creation.content_hash)
    expect(first.content_hash).to match(/\A\h{64}\z/)
    expect(second.previous_hash).to eq(first.content_hash)
    expect(second.content_hash).to eq(Accounting::AuditLog.digest(second))
  end

  it "keeps one chain per entity" do
    log("a")
    other = create(:entity)
    other_log = ActsAsTenant.with_tenant(other) { Accounting::AuditLog.record!(auditable: account, action: "x") }
    expect(other_log.previous_hash).to be_nil
  end

  it "stores the request context, taking it from Current" do
    Current.user = create(:user)
    Current.ip_address = "10.0.0.1"
    Current.user_agent = "RSpec"
    Current.request_id = "req-1"
    Current.reason = "typo in label"
    entry = log
    expect(entry).to have_attributes(ip_address: "10.0.0.1", user_agent: "RSpec", request_id: "req-1", reason: "typo in label", user_id: Current.user.id)
  end

  describe Accounting::AuditVerifier do
    def tamper(entry, **changes)
      conn = ApplicationRecord.connection
      conn.execute("ALTER TABLE accounting_audit_logs DISABLE TRIGGER enforce_audit_log_immutability")
      Accounting::AuditLog.where(id: entry.id).update_all(changes)
    ensure
      conn.execute("ALTER TABLE accounting_audit_logs ENABLE TRIGGER enforce_audit_log_immutability")
    end

    it "reports an intact chain with its length" do
      3.times { |i| log("a#{i}") }
      result = described_class.call(entity: entity)
      expect(result).to be_intact
      expect(result.count).to eq(Accounting::AuditLog.where(entity_id: entity.id).count)
      expect(result.count).to be >= 3
    end

    it "names the exact first broken entry when a row is edited outside the application" do
      log("a")
      victim = log("b", payload: { amount: "10.00" })
      log("c")
      tamper(victim, payload: { amount: "1.00" })
      result = described_class.call(entity: entity)
      expect(result).not_to be_intact
      expect(result.broken_id).to eq(victim.id)
    end

    it "detects a row inserted into the middle of the chain" do
      a = log("a")
      log("b")
      forged = tamper_insert(after: a)
      expect(described_class.call(entity: entity).broken_id).to be_in([ forged, a.id + 1 ].compact)
    end

    it "ignores legacy rows written before the chain existed" do
      Accounting::AuditLog.connection.execute("ALTER TABLE accounting_audit_logs DISABLE TRIGGER enforce_audit_log_immutability")
      Accounting::AuditLog.where(entity_id: entity.id).delete_all
      Accounting::AuditLog.connection.execute("ALTER TABLE accounting_audit_logs ENABLE TRIGGER enforce_audit_log_immutability")
      legacy = Accounting::AuditLog.new(auditable_type: "Accounting::Account", auditable_id: account.id, action: "old", entity_id: entity.id)
      legacy.save!
      log("new")
      expect(described_class.call(entity: entity)).to be_intact
    end

    def tamper_insert(after:)
      row = after.dup
      row.id = nil
      row.action = "forged"
      row.save!
      row.id
    end
  end
end

RSpec.describe "rake audit:verify", type: :model do
  include_context "with entity"

  before(:all) { require "rake"; Rails.application.load_tasks unless Rake::Task.task_defined?("audit:verify") }
  before { Rake::Task["audit:verify"].reenable }

  it "prints the chain length for an intact entity and exits non-zero naming the broken row otherwise" do
    account = create(:account)
    expect { Rake::Task["audit:verify"].invoke }.to output(/#{Regexp.escape(entity.name)}: intact on \d+ entries/).to_stdout

    victim = Accounting::AuditLog.where(entity_id: entity.id).last
    ApplicationRecord.connection.execute("ALTER TABLE accounting_audit_logs DISABLE TRIGGER enforce_audit_log_immutability")
    Accounting::AuditLog.where(id: victim.id).update_all(action: "tampered")
    ApplicationRecord.connection.execute("ALTER TABLE accounting_audit_logs ENABLE TRIGGER enforce_audit_log_immutability")
    Rake::Task["audit:verify"].reenable
    expect { expect { Rake::Task["audit:verify"].invoke }.to raise_error(SystemExit) }.to output(/BROKEN at entry ##{victim.id}/).to_stdout
    expect(account).to be_present
  end
end

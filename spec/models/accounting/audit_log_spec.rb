require 'rails_helper'

RSpec.describe Accounting::AuditLog, type: :model do
  include_context 'with entity'

  let!(:account) { create(:account) }

  describe 'création' do
    it 'crée une entrée de log via .record!' do
      expect {
        Accounting::AuditLog.record!(
          auditable: account,
          action:    'update_balance',
          user:      nil,
          payload:   { amount: '1000.00' }
        )
      }.to change(Accounting::AuditLog, :count).by(1)
    end

    it 'stocke le type et l id de l objet audité' do
      log = Accounting::AuditLog.record!(auditable: account, action: 'test')
      expect(log.auditable_type).to eq('Accounting::Account')
      expect(log.auditable_id).to eq(account.id)
    end

    it 'stocke le payload JSON' do
      log = Accounting::AuditLog.record!(
        auditable: account,
        action:    'post_entry',
        payload:   { reference: 'ACH2025/0001' }
      )
      expect(log.payload['reference']).to eq('ACH2025/0001')
    end
  end

  describe 'immuabilité DB' do
    it 'lève une erreur lors d une tentative de suppression directe en DB' do
      log = Accounting::AuditLog.record!(auditable: account, action: 'test')
      expect {
        Accounting::AuditLog.connection.execute(
          "DELETE FROM accounting_audit_logs WHERE id = #{log.id}"
        )
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end

RSpec.describe Accounting::Partner, 'audit trail' do
  include_context 'with entity'

  it 'logs creation and field-level changes' do
    partner = create(:partner, name: 'Old')
    partner.update!(name: 'New')

    logs = Accounting::AuditLog.for_record(partner).chronologic
    expect(logs.map(&:action)).to eq(%w[create update])
    expect(logs.last.payload['changes']['name']).to eq(%w[Old New])
  end
end

# Signature functions (B02a): the portal's people are not `User`s, so the chain records what kind of actor wrote the row.
# A row by a user hashes exactly as before: the chain already written must keep verifying.
RSpec.describe Accounting::AuditLog, 'actor type' do
  include_context 'with entity'

  let(:account) { create(:account) }

  def old_digest(log)
    content = {
      auditable_type: log.auditable_type, auditable_id: log.auditable_id, action: log.action, user_id: log.user_id,
      user_email: log.user_email, payload: log.payload, ip_address: log.ip_address, reason: log.reason,
      request_id: log.request_id, user_agent: log.user_agent, entity_id: log.entity_id,
      created_at: log.created_at.utc.iso8601(6)
    }
    Digest::SHA256.hexdigest("#{log.previous_hash}#{JSON.generate(described_class.canonical(content.as_json))}")
  end

  it 'is a user unless said otherwise' do
    expect(described_class.record!(auditable: account, action: 'test').actor_type).to eq('user')
  end

  it 'hashes a user row exactly as the chain did before the column existed' do
    log = described_class.record!(auditable: account, action: 'test', payload: { a: 1 })

    expect(log.content_hash).to eq(old_digest(log))
  end

  it 'keeps the kind of actor and binds it into the hash' do
    log = described_class.record!(auditable: account, action: 'portal_download', actor_type: 'portal_user')

    expect(log.actor_type).to eq('portal_user')
    expect(log.content_hash).not_to eq(old_digest(log))
  end

  it 'leaves a chain that mixes both kinds intact' do
    described_class.record!(auditable: account, action: 'one')
    described_class.record!(auditable: account, action: 'two', actor_type: 'portal_user')
    described_class.record!(auditable: account, action: 'three')

    result = Accounting::AuditVerifier.call(entity: entity)

    expect(result).to be_intact
    expect(result.count).to be >= 3
  end

  it 'refuses a kind of actor it does not know' do
    expect { described_class.record!(auditable: account, action: 'x', actor_type: 'robot') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end

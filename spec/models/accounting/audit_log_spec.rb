require 'rails_helper'

RSpec.describe Accounting::AuditLog, type: :model do
  include_context 'with entity'

  let(:account) { create(:account) }

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

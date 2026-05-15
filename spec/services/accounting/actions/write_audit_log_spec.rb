require 'rails_helper'

RSpec.describe Accounting::Actions::WriteAuditLog, type: :service do
  include_context 'with_open_fiscal_year'

  let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

  describe '.execute' do
    it 'crée une entrée AuditLog avec l action post_entry' do
      expect {
        ctx = LightService::Context.make(entry: entry)
        described_class.execute(ctx)
      }.to change(Accounting::AuditLog, :count).by(1)

      expect(Accounting::AuditLog.last.action).to eq('post_entry')
    end

    it 'référence l écriture dans l audit log' do
      ctx = LightService::Context.make(entry: entry)
      described_class.execute(ctx)
      log = Accounting::AuditLog.last
      expect(log.auditable_type).to eq('Accounting::JournalEntry')
      expect(log.auditable_id).to eq(entry.id)
    end
  end
end

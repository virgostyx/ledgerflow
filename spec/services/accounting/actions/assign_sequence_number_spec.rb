require 'rails_helper'

RSpec.describe Accounting::Actions::AssignSequenceNumber, type: :service do
  include_context 'with_open_fiscal_year'

  let(:entry) { create(:journal_entry, fiscal_year: fiscal_year) }

  describe '.execute' do
    it 'assigne une référence formatée depuis le journal' do
      ctx = LightService::Context.make(entry: entry)
      described_class.execute(ctx)
      expect(ctx.entry.reference).to match(/\A[A-Z]+\d{4}\/\d{4}\z/)
    end

    it 'utilise next_sequence_number du journal' do
      ctx = LightService::Context.make(entry: entry)
      expect(entry.journal).to receive(:next_sequence_number)
        .with(year: entry.entry_date.year)
        .and_return('ACH2025/0042')
      described_class.execute(ctx)
      expect(ctx.entry.reference).to eq('ACH2025/0042')
    end
  end
end

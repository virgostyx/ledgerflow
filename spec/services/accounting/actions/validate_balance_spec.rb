require 'rails_helper'

RSpec.describe Accounting::Actions::ValidateBalance, type: :service do
  include_context 'with_open_fiscal_year'

  describe '.execute' do
    context 'avec une écriture équilibrée' do
      let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

      it 'retourne un contexte de succès' do
        ctx = LightService::Context.make(entry: entry)
        described_class.execute(ctx)
        expect(ctx).to be_success
      end
    end

    context 'avec une écriture déséquilibrée' do
      let(:entry) { create(:journal_entry, :with_unbalanced_lines, fiscal_year: fiscal_year) }

      it 'échoue avec un message mentionnant déséquilibré' do
        ctx = LightService::Context.make(entry: entry)
        expect { described_class.execute(ctx) }
          .to raise_error(LightService::FailWithRollbackError)
        expect(ctx.message).to include('déséquilibré')
      end
    end
  end
end

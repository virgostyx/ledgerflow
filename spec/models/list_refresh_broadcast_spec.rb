require 'rails_helper'

RSpec.describe 'List refresh broadcasts', type: :model do
  include_context 'with entity'
  include ActiveJob::TestHelper

  {
    invoices: :invoice, journal_entries: :journal_entry, partners: :partner,
    payment_batches: :payment_batch, fiscal_years: :fiscal_year,
    vat_declarations: :vat_declaration, journals: :journal,
    bank_accounts: :bank_account, accounts: :account, analytical_axes: :analytical_axis
  }.each do |name, factory|
    describe factory.to_s do
      let(:record) { create(factory) }
      let(:stream) { [ entity, name ] }

      it_behaves_like 'broadcasts list refresh'
    end
  end
end

require 'rails_helper'

RSpec.describe 'Accounting::LineAllocations', type: :request do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:accountant) { create(:user, role: :accountant) }
  let(:viewer)     { create(:user, role: :budget_user) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:viewer_membership)     { create(:user_entity, :manager, user: viewer, entity: entity) }

  let(:supplier) { create(:partner, :supplier, name: 'Acme Supplies') }
  let(:journal)  { create(:journal, :cash) }

  def line(debit: 0, credit: 0)
    entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
  end

  let!(:bill)    { line(credit: 1000) }
  let!(:payment) { line(debit: 600) }

  before { sign_in accountant }

  describe 'POST /accounting/line_allocations' do
    it 'allocates the payment and goes back to the lettering page' do
      expect { post accounting_line_allocations_path, params: { account_id: account_440.id, line_ids: [ bill.id, payment.id ] } }
        .to change(Accounting::LineAllocation, :count).by(1)

      expect(response).to redirect_to(new_accounting_lettering_path(account_id: account_440.id))
      expect(flash[:notice]).to eq('Payment allocated')
    end

    it 'says the group was lettered when it is fully settled' do
      more = line(debit: 400)
      post accounting_line_allocations_path, params: { account_id: account_440.id, line_ids: [ bill.id, payment.id, more.id ] }

      expect(flash[:notice]).to match(/Settled and lettered \(AA\)/)
    end

    it 'shows the reason when the selection is invalid' do
      expect { post accounting_line_allocations_path, params: { account_id: account_440.id, line_ids: [ bill.id ] } }
        .not_to change(Accounting::LineAllocation, :count)
      expect(flash[:alert]).to eq('Select at least two lines')
    end

    it 'denies a viewer' do
      sign_in viewer
      expect { post accounting_line_allocations_path, params: { account_id: account_440.id, line_ids: [ bill.id, payment.id ] } }
        .not_to change(Accounting::LineAllocation, :count)
    end
  end

  describe 'DELETE /accounting/line_allocations/:id' do
    it 'removes the allocation' do
      Accounting::AllocateLines.call(lines: [ bill, payment ])
      allocation = Accounting::LineAllocation.first

      expect { delete accounting_line_allocation_path(allocation) }.to change(Accounting::LineAllocation, :count).by(-1)
      expect(response).to redirect_to(new_accounting_lettering_path(account_id: account_440.id))
    end

    it 'shows the reason when a line is lettered' do
      Accounting::AllocateLines.call(lines: [ bill, payment ])
      allocation = Accounting::LineAllocation.first
      bill.update_columns(lettering_id: create(:lettering, account: account_440).id)

      delete accounting_line_allocation_path(allocation)
      expect(flash[:alert]).to eq('Remove the lettering first')
    end
  end

  describe 'lettering page' do
    before { Accounting::AllocateLines.call(lines: [ bill, payment ]) }

    it 'lists partly settled allocations and the open amount of each line' do
      get new_accounting_lettering_path(account_id: account_440.id)

      expect(response.body).to include('Partly settled')
      expect(response.body).to include('Acme Supplies')
      expect(response.body).to include('400.00') # open part of the bill
    end
  end
end

require 'rails_helper'

RSpec.describe 'Accounting::Letterings', type: :request do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :budget_user) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager, user: manager, entity: entity) }

  let(:supplier) { create(:partner, :supplier) }
  let(:journal)  { create(:journal, :cash) }

  def line(debit: 0, credit: 0, partner: supplier, account: account_440)
    entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account, partner: partner,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
  end

  before { sign_in accountant }

  describe 'GET /accounting/letterings/new' do
    it 'renders the account picker' do
      get new_accounting_lettering_path
      expect(response).to have_http_status(:ok)
    end

    it 'is reachable from the sidebar' do
      get accounting_root_path
      expect(response.body).to include(%(href="#{new_accounting_lettering_path}"))
    end

    it 'offers leaf accounts and reconcilable header accounts, but not plain headers' do
      account_400.update!(is_leaf: false, reconcilable: true)
      header = create(:account, code: '600000', is_leaf: false, reconcilable: false)

      get new_accounting_lettering_path

      expect(response.body).to include(%(value="#{account_400.id}"))
      expect(response.body).to include(%(value="#{account_570.id}"))
      expect(response.body).not_to include(%(value="#{header.id}"))
    end

    it 'lists the unlettered lines of the chosen account only' do
      open_line = line(credit: 121)
      lettered  = line(debit: 50).tap { |l| l.update_columns(lettering_id: create(:lettering, account: account_440).id) }
      other     = line(credit: 77, account: account_570, partner: nil)

      get new_accounting_lettering_path(account_id: account_440.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("line_ids_#{open_line.id}")
      expect(response.body).not_to include("line_ids_#{lettered.id}")
      expect(response.body).not_to include("line_ids_#{other.id}")
    end
  end

  describe 'POST /accounting/letterings' do
    it 'letters the selected balanced lines' do
      a = line(credit: 121)
      b = line(debit: 121)

      expect { post accounting_letterings_path, params: { line_ids: [ a.id, b.id ] } }
        .to change(Accounting::Lettering, :count).by(1)

      expect(response).to redirect_to(new_accounting_lettering_path(account_id: account_440.id))
      expect(a.reload.lettering).to eq(b.reload.lettering)
    end

    it 're-renders with the reason when the group does not balance' do
      a = line(credit: 121)
      b = line(debit: 100)

      expect { post accounting_letterings_path, params: { line_ids: [ a.id, b.id ] } }
        .not_to change(Accounting::Lettering, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Debits and credits must balance')
    end

    it 'ignores lines of other entities' do
      foreign = ActsAsTenant.without_tenant { create(:entity) }
      other_line = ActsAsTenant.with_tenant(foreign) do
        acc = create(:account, code: '440000')
        entry = create(:journal_entry, status: :posted, fiscal_year: create(:fiscal_year))
        ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
        create(:journal_entry_line, journal_entry: entry, account: acc, credit: 5)
      end

      post accounting_letterings_path, params: { line_ids: [ other_line.id ] }

      expect(other_line.reload.lettering_id).to be_nil
    end

    it 'denies a manager' do
      sign_in manager
      a = line(credit: 5)
      b = line(debit: 5)

      expect { post accounting_letterings_path, params: { line_ids: [ a.id, b.id ] } }
        .not_to change(Accounting::Lettering, :count)
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe 'DELETE /accounting/letterings/:id' do
    it 'removes the lettering' do
      a = line(credit: 5)
      b = line(debit: 5)
      lettering = Accounting::LetterLines.call(lines: [ a, b ]).lettering

      expect { delete accounting_lettering_path(lettering) }.to change(Accounting::Lettering, :count).by(-1)
      expect(response).to redirect_to(new_accounting_lettering_path(account_id: account_440.id))
      expect(a.reload.lettering_id).to be_nil
    end
  end
end

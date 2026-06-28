require 'rails_helper'

RSpec.describe 'Accounting::JournalEntries', type: :request do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }
  let!(:journal)   { create(:journal, :purchase) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }

  before { sign_in accountant }

  describe 'GET /accounting/journal_entries' do
    it 'retourne 200' do
      get accounting_journal_entries_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/journal_entries/new' do
    it 'retourne 200' do
      get new_accounting_journal_entry_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounting/journal_entries' do
    context 'avec des lignes équilibrées → crée et valide' do
      let(:valid_params) do
        {
          accounting_journal_entry: {
            journal_id:     journal.id,
            fiscal_year_id: fiscal_year.id,
            entry_date:     Date.current,
            description:    'Test écriture',
            lines_attributes: {
              '0' => { account_id: account_604.id, debit: '1000.00', credit: '0', label: 'Charges' },
              '1' => { account_id: account_440.id, debit: '0', credit: '1000.00', label: 'Fournisseur' }
            }
          }
        }
      end

      it 'crée une écriture' do
        expect {
          post accounting_journal_entries_path, params: valid_params.merge(commit: 'Save')
        }.to change(Accounting::JournalEntry, :count).by(1)
      end

      it 'valide l écriture' do
        post accounting_journal_entries_path, params: valid_params.merge(commit: 'Save')
        expect(Accounting::JournalEntry.last).to be_posted
      end

      it 'redirige vers l écriture' do
        post accounting_journal_entries_path, params: valid_params.merge(commit: 'Save')
        expect(response).to redirect_to(accounting_journal_entry_path(Accounting::JournalEntry.last))
      end
    end

    context 'avec des annotations analytiques' do
      let!(:axis)         { create(:analytical_axis, :proj) }
      let!(:anal_account) { create(:analytical_account, analytical_axis: axis,
                                   code: 'PROJ-001', label_fr: 'Project Alpha') }

      it 'crée les annotations avec l écriture' do
        expect {
          post accounting_journal_entries_path, params: {
            commit: 'Save',
            accounting_journal_entry: {
              journal_id:     journal.id,
              fiscal_year_id: fiscal_year.id,
              entry_date:     Date.current,
              description:    'Charges projet',
              lines_attributes: {
                '0' => {
                  account_id: account_604.id, debit: '500.00', credit: '0', label: 'Projet',
                  analytical_annotations_attributes: {
                    '0' => { analytical_axis_id: axis.id, analytical_account_id: anal_account.id }
                  }
                },
                '1' => { account_id: account_440.id, debit: '0', credit: '500.00', label: 'Fournisseur' }
              }
            }
          }
        }.to change(Accounting::AnalyticalAnnotation, :count).by(1)
      end
    end

    context 'sans date' do
      it 'retourne 422' do
        post accounting_journal_entries_path, params: {
          accounting_journal_entry: {
            journal_id: journal.id, fiscal_year_id: fiscal_year.id,
            lines_attributes: {}
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'quand PostJournalEntry échoue après sauvegarde' do
      let(:valid_params) do
        {
          accounting_journal_entry: {
            journal_id:     journal.id,
            fiscal_year_id: fiscal_year.id,
            entry_date:     Date.current,
            description:    'Test',
            lines_attributes: {
              '0' => { account_id: account_604.id, debit: '500.00', credit: '0', label: 'Charges' },
              '1' => { account_id: account_440.id, debit: '0', credit: '500.00', label: 'Fournisseur' }
            }
          }
        }
      end

      before do
        allow(Accounting::PostJournalEntry).to receive(:call).and_return(
          double('result', success?: false, message: 'posting error')
        )
      end

      it 'retourne 422 et ne conserve pas l écriture' do
        expect {
          post accounting_journal_entries_path, params: valid_params.merge(commit: 'Save')
        }.not_to change(Accounting::JournalEntry, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /accounting/journal_entries/:id' do
    let(:entry) { create(:journal_entry, :posted, fiscal_year: fiscal_year) }

    it 'retourne 200' do
      get accounting_journal_entry_path(entry)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/journal_entries/:id/edit' do
    let(:entry) { create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year) }

    it 'retourne 200' do
      get edit_accounting_journal_entry_path(entry)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /accounting/journal_entries/:id' do
    let(:entry) { create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year) }

    it 'met à jour et redirige' do
      patch accounting_journal_entry_path(entry), params: {
        accounting_journal_entry: {
          journal_id: journal.id,
          fiscal_year_id: fiscal_year.id,
          entry_date: Date.current,
          description: 'Description mise à jour',
          lines_attributes: {}
        }
      }
      expect(response).to redirect_to(accounting_journal_entry_path(entry))
    end

    it 'retourne 422 si invalide' do
      patch accounting_journal_entry_path(entry), params: {
        accounting_journal_entry: { entry_date: '' }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /accounting/journal_entries/:id/post_entry' do
    let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

    it 'valide l écriture brouillon' do
      post post_entry_accounting_journal_entry_path(entry)
      expect(entry.reload).to be_posted
      expect(response).to redirect_to(accounting_journal_entry_path(entry))
    end
  end

  describe 'POST /accounting/journal_entries/:id/reverse' do
    let(:entry) { create(:journal_entry, :posted, fiscal_year: fiscal_year) }

    it 'retourne une alerte non implémenté' do
      post reverse_accounting_journal_entry_path(entry)
      expect(response).to redirect_to(accounting_journal_entry_path(entry))
    end
  end

  describe 'accès manager' do
    before { sign_in manager }

    it 'GET index retourne 200' do
      get accounting_journal_entries_path
      expect(response).to have_http_status(:ok)
    end

    it 'POST create est refusé' do
      post accounting_journal_entries_path, params: { accounting_journal_entry: { journal_id: journal.id } }
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end

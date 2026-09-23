require 'rails_helper'

RSpec.describe 'Accounting::VatDeclarations', type: :request do
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }

  before { sign_in accountant }

  describe 'GET /accounting/vat_declarations' do
    it 'retourne 200' do
      get accounting_vat_declarations_path
      expect(response).to have_http_status(:ok)
    end

    describe 'filtres' do
      let!(:draft_decl)     { create(:vat_declaration, fiscal_year: fiscal_year, period_type: :quarterly) }
      let!(:submitted_decl) { create(:vat_declaration, fiscal_year: fiscal_year, status: :submitted, period_type: :monthly, period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 4, 30)) }

      it 'filtre par statut' do
        get accounting_vat_declarations_path, params: { q: { status: 'submitted' } }
        expect(response.body).to include(accounting_vat_declaration_path(submitted_decl)).and not_include(accounting_vat_declaration_path(draft_decl))
      end

      it 'filtre par type de période' do
        get accounting_vat_declarations_path, params: { q: { period_type: 'quarterly' } }
        expect(response.body).to include(accounting_vat_declaration_path(draft_decl)).and not_include(accounting_vat_declaration_path(submitted_decl))
      end
    end
  end

  describe 'GET /accounting/vat_declarations with column filters' do
    let!(:quarterly) { create(:vat_declaration, fiscal_year: fiscal_year, period_type: :quarterly, period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31)) }
    let!(:monthly)   { create(:vat_declaration, fiscal_year: fiscal_year, status: :submitted, period_type: :monthly, period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 4, 30)) }

    it 'filters on status, period type and period start' do
      get accounting_vat_declarations_path, params: { f: { status: %w[submitted] } }
      expect(response.body).to include(accounting_vat_declaration_path(monthly)).and not_include(accounting_vat_declaration_path(quarterly))
      get accounting_vat_declarations_path, params: { f: { period_type: %w[quarterly] } }
      expect(response.body).to include(accounting_vat_declaration_path(quarterly)).and not_include(accounting_vat_declaration_path(monthly))
      get accounting_vat_declarations_path, params: { f: { period_start: { from: '2025-03-01' } } }
      expect(response.body).to include(accounting_vat_declaration_path(monthly)).and not_include(accounting_vat_declaration_path(quarterly))
    end

    it 'keeps only the fiscal year select in the panel' do
      get accounting_vat_declarations_path
      expect(response.body).to include('name="q[fiscal_year_id]"')
      expect(response.body).not_to include('name="q[status]"', 'name="q[period_type]"')
    end
  end

  describe 'GET /accounting/vat_declarations/new' do
    it 'retourne 200' do
      get new_accounting_vat_declaration_path
      expect(response).to have_http_status(:ok)
    end

    it "préremplit period_type avec la périodicité de dépôt de l entité" do
      entity.update!(vat_filing_frequency: :quarterly)
      get new_accounting_vat_declaration_path
      expect(response.body).to include('<option selected="selected" value="quarterly">Quarterly</option>')
    end
  end

  describe 'POST /accounting/vat_declarations — entité en franchise' do
    it 'retourne 422' do
      entity.update!(vat_regime: :franchise)
      post accounting_vat_declarations_path, params: {
        accounting_vat_declaration: {
          fiscal_year_id: fiscal_year.id,
          period_type:    'quarterly',
          period_start:   Date.new(2025, 1, 1).iso8601,
          period_end:     Date.new(2025, 3, 31).iso8601
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /accounting/vat_declarations' do
    let(:valid_params) do
      {
        accounting_vat_declaration: {
          fiscal_year_id: fiscal_year.id,
          period_type:    'quarterly',
          period_start:   Date.new(2025, 1, 1).iso8601,
          period_end:     Date.new(2025, 3, 31).iso8601
        }
      }
    end

    it 'crée une déclaration TVA' do
      expect {
        post accounting_vat_declarations_path, params: valid_params
      }.to change(Accounting::VatDeclaration, :count).by(1)
    end

    it 'redirige vers la déclaration créée' do
      post accounting_vat_declarations_path, params: valid_params
      expect(response).to redirect_to(
        accounting_vat_declaration_path(Accounting::VatDeclaration.last)
      )
    end

    context 'avec des paramètres invalides' do
      it 'retourne 422 sans période' do
        post accounting_vat_declarations_path, params: {
          accounting_vat_declaration: {
            fiscal_year_id: fiscal_year.id,
            period_type:    'quarterly'
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'retourne 422 si period_end < period_start' do
        post accounting_vat_declarations_path, params: {
          accounting_vat_declaration: {
            fiscal_year_id: fiscal_year.id,
            period_type:    'quarterly',
            period_start:   Date.new(2025, 3, 31).iso8601,
            period_end:     Date.new(2025, 1, 1).iso8601
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /accounting/vat_declarations/:id' do
    let(:declaration) { create(:vat_declaration, fiscal_year: fiscal_year) }

    it 'retourne 200' do
      get accounting_vat_declaration_path(declaration)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'accès manager' do
    before { sign_in manager }

    it 'GET index retourne 200' do
      get accounting_vat_declarations_path
      expect(response).to have_http_status(:ok)
    end

    it 'POST create est refusé' do
      post accounting_vat_declarations_path, params: {
        accounting_vat_declaration: { fiscal_year_id: fiscal_year.id }
      }
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end

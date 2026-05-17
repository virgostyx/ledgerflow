Rails.application.routes.draw do
  # Landing page publique
  root "landing#index"

  # Devise — authentification
  devise_for :users, controllers: {
    sessions:      "users/sessions",
    passwords:     "users/passwords",
    registrations: "users/registrations"
  }

  # Application comptable (authentifié)
  authenticate :user do
    namespace :accounting do
      root to: "dashboard#index"

      resources :partners

      resources :journal_entries do
        member do
          post :post_entry
          post :reverse
        end
      end

      resources :invoices do
        member do
          post :validate_invoice
          post :send_peppol
        end
      end

      resources :vat_declarations, only: [ :index, :new, :create, :show ]

      resources :fiscal_years do
        member { post :close }
      end

      resource  :bank_reconciliation, only: [ :show, :update ]

      namespace :reports do
        get :trial_balance
        get :balance_sheet
        get :income_statement
        get :general_ledger
        get :analytic_by_project
        get :analytic_by_axis
        get :analytic_cross
      end

      namespace :settings do
        root to: "dashboard#index"
        resources :journals do
          member { patch :toggle_active }
        end
        resources :bank_accounts
        resources :accounts, only: [ :index, :show, :new, :create, :edit, :update ]
        resources :analytical_axes do
          resources :analytical_accounts, shallow: true
        end
      end
    end
  end

  # API BudgetFlow (JWT)
  namespace :api do
    namespace :v1 do
      resources :journal_entries, only: [ :index, :show, :create ]
      resources :invoices,        only: [ :index, :show ]
      resources :projects,        only: [] do
        get :accounting_summary, on: :member
      end
    end
  end

  # Webhooks Peppol (public, HMAC-signed)
  post "/peppol/webhooks", to: "peppol/webhooks#receive"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end

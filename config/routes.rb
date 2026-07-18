Rails.application.routes.draw do
  # Landing page publique
  root "landing#index"

  # Devise — authentification
  devise_for :users, controllers: {
    sessions:      "users/sessions",
    passwords:     "users/passwords",
    registrations: "users/registrations"
  }

  # Onboarding (pas de tenant requis — le user vient de s'inscrire)
  namespace :onboarding do
    resource :entity, only: %i[new create]
  end

  # Gestion des entités (tenant switching)
  resources :entities, only: %i[index new create] do
    member { post :switch }
  end

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

      # Sales (customer invoices)
      get  "sales",         to: "invoices#index",  as: :sales,         defaults: { invoice_type: "customer" }
      get  "sales/new",     to: "invoices#new",    as: :new_sales,     defaults: { invoice_type: "customer" }
      post "sales",         to: "invoices#create",                     defaults: { invoice_type: "customer" }

      # Purchases (supplier invoices)
      get  "purchases",     to: "invoices#index",  as: :purchases,     defaults: { invoice_type: "supplier" }
      get  "purchases/new", to: "invoices#new",    as: :new_purchases, defaults: { invoice_type: "supplier" }
      post "purchases",     to: "invoices#create",                     defaults: { invoice_type: "supplier" }

      # Individual invoice actions — URLs inchangées
      resources :invoices, only: [ :show, :edit, :update, :destroy ] do
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

      resources :payment_batches, only: [ :index, :new, :create, :show, :destroy ] do
        member do
          post :generate
          post :execute
          get  :download
        end
      end

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

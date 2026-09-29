Rails.application.routes.draw do
  # Landing page publique
  get "/favicon.ico", to: redirect("/icon.png")
  root "landing#index"

  # Devise — authentification
  devise_for :users, controllers: {
    sessions:      "users/sessions",
    passwords:     "users/passwords",
    registrations: "users/registrations"
  }

  devise_scope :user do
    get  "passkey_session/options",   to: "users/passkey_sessions#options", as: :passkey_session_options
    post "passkey_session",           to: "users/passkey_sessions#create"
    get  "recovery_code_session/new", to: "users/recovery_code_sessions#new", as: :new_recovery_code_session
    post "recovery_code_session",     to: "users/recovery_code_sessions#create", as: :recovery_code_session
  end

  resources :passkeys, only: %i[index create destroy], controller: "users/passkeys" do
    get :options, on: :collection
  end

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

      get "column_values/:resource/:column", to: "column_values#show", as: :column_values

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
          post :cancel_invoice
          post :send_peppol
          post :create_credit_note
          post :apply_credit_note
          get  :pdf
          post :send_email
          post :duplicate
        end
      end

      resources :vat_declarations, only: [ :index, :new, :create, :show ] do
        member do
          post :submit
          post :accept
          get  :intervat_xml
        end
      end

      resources :intracom_listings, only: [ :index, :new, :create, :show ]

      resources :recurring_invoices, except: [ :show ]
      resources :payment_reminders, only: [ :index, :create ]
      resources :consistency_runs, path: "consistency", only: [ :index, :create ] do
        post :acknowledge, on: :collection
      end

      resource :closing_bundle, only: [ :show ] do
        get :bundle
        get :audit_export
        get :filing_data
      end

      resources :audit_logs, only: [ :index, :show ]

      resources :accruals, only: [ :index, :new, :create, :destroy ] do
        member do
          post :book
          post :reverse
        end
      end

      resources :fixed_assets, except: [ :show ] do
        post :post_depreciation, on: :collection
        member do
          get  :disposal
          post :dispose
        end
      end

      resources :letterings, only: [ :new, :create, :destroy ]
      resources :line_allocations, only: [ :create, :destroy ]

      resources :fiscal_years do
        member do
          post :close
          get  :vat_regularization
          post :regularize_prorata
          post :review_fixed_assets
        end
      end

      resource :bank_reconciliation, only: [ :show, :update ] do
        get :allocate
      end

      resources :payment_batches, only: [ :index, :new, :create, :show, :destroy ] do
        member do
          post :generate
          post :execute
          get  :download
        end
      end

      resources :cash_forecast_items, only: [ :create, :destroy ]

      namespace :reports do
        get :trial_balance
        get :cash_forecast
        get :cash_flow
        get :fixed_asset_movements
        get :balance_sheet
        get :income_statement
        get :annual_accounts
        get :aged_balance
        get :unlettered_lines
        get :annual_customer_listing
        get :general_ledger
        get  :bank_reconciliation_report
        post :freeze_bank_reconciliation_report
        get :journal_summary
        get :analytic_by_project
        get :analytic_by_axis
        get :analytic_cross
        get :analytic_pivot
        get :analytic_margin
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
        resource :vat_settings, only: [ :edit, :update ]
        resource :peppol_settings, only: [ :edit, :update ] do
          post :simulate_incoming
        end
        resource :entity, only: [ :edit, :update ]
        resources :api_clients, only: [ :index, :new, :create ] do
          member do
            post  :rotate
            patch :revoke
          end
        end
        resource :opening_balance, only: [ :show, :create ] do
          get :template
        end
      end
    end
  end

  # API BudgetFlow (JWT)
  namespace :api do
    namespace :v1 do
      resources :journal_entries, only: [ :index, :show, :create ]
      resources :invoices,        only: [ :index, :show ]
      resources :partners,        only: [ :update ], param: :external_ref, constraints: { external_ref: %r{[^/]+} }
      resources :projects,        only: [] do
        get :accounting_summary, on: :member
      end
    end
  end

  # Webhooks Peppol (public; the token designates the entity, the signature is checked with its Access Point secret)
  post "/peppol/webhooks/:token", to: "peppol/webhooks#receive", as: :peppol_webhook

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end

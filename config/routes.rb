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

  resource :two_factor, only: %i[show create destroy], controller: "users/two_factor" do
    post :backup_codes
  end
  get  "two_factor/challenge", to: "users/two_factor#challenge", as: :two_factor_challenge
  post "two_factor/challenge", to: "users/two_factor#verify"

  resources :passkeys, only: %i[index create destroy], controller: "users/passkeys" do
    get :options, on: :collection
  end

  # Onboarding (pas de tenant requis — le user vient de s'inscrire)
  namespace :onboarding do
    resource :entity, only: %i[new create]
  end

  # F12a: the portfolio of the dossiers a person works in, and the organizations that gather them
  get   "portfolio", to: "portfolio#index"
  post  "portfolio/refresh", to: "portfolio#refresh", as: :portfolio_refresh
  post  "portfolio/bulk", to: "portfolio#bulk", as: :portfolio_bulk
  patch "portfolio/:entity_id/responsible", to: "portfolio#responsible", as: :portfolio_responsible
  resources :organizations, only: %i[index new create show update] do
    member do
      post   :add_entity
      delete "entities/:entity_id", action: :remove_entity, as: :remove_entity
      post   :add_member
      delete "members/:membership_id", action: :remove_member, as: :remove_member
    end
  end

  # A01: the AI agent's panel. A conversation is its author's alone; the answer is written in the background and streamed back (Turbo Streams).
  namespace :agent do
    resource :setting, only: %i[show update]
    resources :security_events, only: :index
    resources :knowledge_documents, only: %i[index show new create] do
      member do
        post :review
        post :retire
        get :new_version
      end
    end
    resources :knowledge_gaps, only: :index
    resources :proposals, only: [] do
      member do
        post :accept
        post :reject
        get :modify
      end
    end
    post "messages/:message_id/proposals/accept_all", to: "proposals#accept_all", as: :accept_all_proposals
    resources :reviews, only: %i[index create show]
    resource :privacy, only: :show, controller: "privacy"
    resources :subject_requests, only: %i[new create]
    resources :conversations, only: %i[index show create update destroy] do
      get :export, on: :collection
      resource :stop, only: :create
      resources :messages, only: :create do
        get :sent, on: :member
        post :verify, on: :member
        resource :feedback, only: :create
      end
    end
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

      resources :partners do
        post :validate, on: :member
      end

      resources :journal_entries do
        member do
          post :post_entry
          post :reverse
          get  :reversal
          post :duplicate
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
          post :return_invoice
          post :send_peppol
          post :peppol_fallback_email
          post :create_credit_note
          post :apply_credit_note
          get  :pdf
          get  "documents/:kind", action: :document, as: :document
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
      get "exchange_rate_lookup", to: "exchange_rates#lookup", as: :exchange_rate_lookup # F11: the rate a form shows (JSON)
      # F09: customer dunning (replaces the manual reminders above once the feature is on)
      resources :dunning_runs, only: %i[index show create] do
        post :send_run, on: :member
      end
      resources :dunning_items, only: %i[show update] do
        member do
          get  :pdf
          post :bounce
        end
      end
      resources :dunning_lines, only: [] do
        member do
          patch :dispute
          patch :promise
        end
      end
      resource :dunning_policy, only: %i[show update]
      resources :documents, only: %i[index create show update destroy] do
        member do
          get  :file
          get  :download
          post :archive
          post :confirm_field
          post :rerun
          post :create_invoice
          post :split
          post :legal_hold
        end
      end
      resources :document_links, only: %i[create destroy]
      resources :period_locks, path: "periods", only: %i[index create] do
      post :lock_months, on: :collection
        post :unlock, on: :member
      end
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

      resources :entry_templates, except: [ :show ] do
        member do
          get  :entry
          post :create_entry
        end
        post :examples, on: :collection
      end

      resources :recurring_entries, except: [ :show ] do
        member do
          post :pause
          post :resume
          post :skip
          post :approve_post
        end
      end

      resources :peppol_messages, only: %i[index show] do
        member do
          get  :pdf
          post :reprocess
          post :dismiss
          post :assign_supplier
          post :resend
        end
        post :reprocess_all, on: :collection
      end

      resources :tasks, only: %i[index show new create edit update] do
        member do
          post :external_link
          post :revoke_external_link
        end
      end
      resources :comments, only: %i[create update] do
        member do
          post :hide
          post :resolve
          post :reopen
        end
      end
      resource :notification_preferences, only: %i[edit update]
      resources :notifications, only: :index do
        post :read, on: :member
        post :read_all, on: :collection
      end

      resources :letterings, only: [ :new, :create, :destroy, :show ]
      resources :lettering_write_offs, only: :create
      resources :lettering_suggestions, only: :create do
        member do
          post :accept
          post :reject
        end
        collection do
          post :preview
          post :accept_batch
        end
      end
      resources :line_allocations, only: [ :create, :destroy ]

      # F12b: consolidation of a group of companies
      resources :consolidation_groups, only: %i[index new create show] do
        member do
          post   :add_member
          delete "members/:member_id", action: :remove_member, as: :remove_member
          post   "members/:member_id/stakes", action: :add_stake, as: :add_stake
          post   :add_mapping
          delete "mappings/:mapping_id", action: :remove_mapping, as: :remove_mapping
          post   :add_validation
          post   "validations/:validation_id/revoke", action: :revoke_validation, as: :revoke_validation
        end
      end
      resources :consolidation_runs, only: %i[show create] do
        member do
          post :compute
          post :validate
          post :freeze
          get  "entries/new", action: :new_entry, as: :new_entry
          post :create_entry
          delete "entries/:entry_id", action: :destroy_entry, as: :destroy_entry
          get :export
        end
      end

      # F13a: guided imports of partners, accounts and entries
      resources :imports, only: %i[index new create show update] do
        member do
          post :simulate
          post :run
          post :undo
        end
      end

      # F13b: data exports (streamed) and the full backup
      resources :data_exports, only: :index do
        post :backup, on: :collection
        get  "download/:token", action: :download, on: :collection, as: :download
      end
      get "data_exports/file", to: "data_exports#show", as: :data_export_file

      # F10: the guided closing of a fiscal year
      resources :closing_runs, only: %i[index show create] do
        patch :settings, on: :collection
        member do
          post :validate_entries
          post :approve
          post :appropriate
          post :reopen
          get  :bundle
        end
        resources :steps, controller: "closing_steps", param: :code, only: [] do
          member do
            post :perform
            post :acknowledge
            post :skip
            post :confirm
            post :comment
          end
        end
      end

      resources :fiscal_years do
        member do
          post :close
          get  :vat_regularization
          get  :revaluation
          post :propose_revaluation
          post :regularize_prorata
          post :review_fixed_assets
        end
      end

      resource :bank_reconciliation, only: [ :show, :update ] do
        get :allocate
      end
      resources :bank_statements, only: %i[index show new create]

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
        resources :exchange_rates, only: [ :index, :create, :destroy ] do
          collection do
            post  :import_ecb
            post  :import_inforeuro
            post  :import_csv
            patch :rules
          end
        end
        resources :accounts, only: [ :index, :show, :new, :create, :edit, :update ]
        resources :analytical_axes do
          resources :analytical_accounts, shallow: true
        end
        resource :vat_settings, only: [ :edit, :update ]
        resource :peppol_mappings, only: [ :edit, :update ]
        resource :peppol_settings, only: [ :edit, :update ] do
          post :simulate_incoming
        end
        resource :entity, only: [ :edit, :update ] do
          post :regenerate_documents_address
          post :create_rounding_accounts
        end
        resources :memberships, only: %i[index create update] do
          post :reset_two_factor, on: :member
        end
        resources :custom_roles, only: %i[index create update destroy]
        resources :bank_rules, only: %i[index update destroy]
        resources :webhook_subscriptions, except: :show do # F13c
          member do
            get  :deliveries
            post :rotate_secret
            post :resume
            post "deliveries/:delivery_id/replay", action: :replay, as: :replay_delivery
          end
        end
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

  # The public API: its documentation (F13c)
  get "/api/docs", to: "api/docs#show"
  get "/api/v1/openapi.json", to: "api/docs#openapi"

  # API BudgetFlow (JWT) and public API (personal tokens)
  namespace :api do
    namespace :v1 do
      get :ping, to: "ping#show"

      # F13c: the public API (personal tokens, problem+json, cursor pagination): the read-only collections come from Api::V1::Resources
      get "reports/:name", to: "public/reports#show", as: :public_report
      resources :entries, only: %i[index show create update], controller: "public/entries", constraints: { id: /\d+/ } do
        member do
          post :post
          post :reverse
        end
      end
      Api::V1::Resources::REGISTRY.each_key do |name|
        get name, to: "public/resources#index", defaults: { resource: name }, as: "public_#{name}"
        get "#{name}/:id", to: "public/resources#show", defaults: { resource: name }, as: "public_#{name.singularize}", constraints: { id: /\d+/ }
      end
      # A01: the AI agent (personal tokens, scope agent:use). The answer is written in the background: a question is accepted (202) and the conversation read until it is no longer answering.
      scope "agent", constraints: { id: /\d+/, message_id: /\d+/ } do
        get    "conversations", to: "public/agent_conversations#index", as: :agent_conversations
        post   "conversations", to: "public/agent_conversations#create"
        get    "conversations/:id", to: "public/agent_conversations#show", as: :agent_conversation
        patch  "conversations/:id", to: "public/agent_conversations#update"
        delete "conversations/:id", to: "public/agent_conversations#destroy"
        post   "conversations/:id/stop", to: "public/agent_conversations#stop", as: :stop_agent_conversation
        post   "conversations/:id/messages", to: "public/agent_messages#create", as: :agent_messages
        post   "conversations/:id/messages/:message_id/feedback", to: "public/agent_feedback#create", as: :agent_feedback
      end
      resources :invoice_events, only: [ :index ]
      resources :incoming_invoices, only: [] do
        member do
          post :claim
          get  "documents/:kind", action: :document, as: :document
        end
      end
      resources :journal_entries, only: [ :index, :show ]
      resources :invoices,        only: [ :index, :show, :update, :destroy ], param: :external_ref, constraints: { external_ref: %r{[^/]+} }
      resources :partners,        only: [ :update ], param: :external_ref, constraints: { external_ref: %r{[^/]+} }
      resources :projects,        only: [] do
        get :accounting_summary, on: :member
      end
    end
  end

  # Webhooks Peppol (public; the token designates the entity, the signature is checked with its Access Point secret)
  # F08: a third party answers a question through a signed link, with no account
  get  "/reply/:token", to: "external_replies#show", as: :external_reply
  post "/reply/:token", to: "external_replies#create"
  post "/peppol/webhooks/:token", to: "peppol/webhooks#receive", as: :peppol_webhook

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end

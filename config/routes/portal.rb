# The routes of the client portal (B02a): drawn only for the portal host, see Portal::HostConstraint.
scope module: :portal do
  root "home#show", as: :portal_root

  get    "sign_in", to: "sessions#new", as: :portal_sign_in
  post   "session", to: "sessions#create", as: :portal_session
  delete "session", to: "sessions#destroy"

  get  "invitations/:token", to: "invitations#show", as: :portal_invitation
  post "invitations/:token", to: "invitations#accept"

  get  "second_factor/new", to: "second_factors#new", as: :new_portal_second_factor
  post "second_factor", to: "second_factors#create", as: :portal_second_factor
  get  "second_factor/challenge", to: "second_factors#challenge", as: :portal_second_factor_challenge
  post "second_factor/challenge", to: "second_factors#verify"

  get "manifest.webmanifest", to: "service_worker#manifest", as: :portal_manifest
  get "service-worker.js", to: "service_worker#worker", as: :portal_service_worker
  get "branding.css", to: "branding#stylesheet", as: :branding_stylesheet, defaults: { format: "css" }
  get "branding/logo", to: "branding#logo", as: :branding_logo
  resources :access_requests, only: %i[new create]
  resource :preferences, only: %i[show update]
  resources :devices, only: %i[index destroy], param: :token
  resources :publications, only: %i[index show], param: :token
  resources :uploads, only: %i[index new create show], param: :token do
    member do
      put "chunks/:position", to: "upload_chunks#update", as: :chunk
      post :complete
    end
  end
  resources :questions, only: %i[index show], param: :token do
    post :answer, on: :member
  end
  get "mail", to: "mail#show", as: :portal_mail
  resources :document_requests, only: :index
  post "document_request_lines/:token/answer", to: "document_request_lines#answer", as: :answer_document_request_line
  get "downloads/:signed", to: "downloads#show", as: :portal_download
end

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

  get "branding.css", to: "branding#stylesheet", as: :branding_stylesheet, defaults: { format: "css" }
  get "branding/logo", to: "branding#logo", as: :branding_logo
  resources :access_requests, only: %i[new create]
  resource :preferences, only: %i[show update]
  resources :devices, only: %i[index destroy], param: :token
  resources :publications, only: %i[index show], param: :token
  get "downloads/:signed", to: "downloads#show", as: :portal_download
end

WebAuthn.configure do |config|
  config.rp_name = "LedgerFlow"
  config.encoding = :base64url

  config.allowed_origins = if Rails.env.production?
    [ "https://ledgerflow.budgetflowmanagement.com" ]
  elsif Rails.env.test?
    [ "https://webauthn.test" ]
  else
    [ "http://localhost:3000" ]
  end
end

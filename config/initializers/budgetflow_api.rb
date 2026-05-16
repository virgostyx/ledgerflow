BUDGETFLOW_API_URL    = ENV.fetch("BUDGETFLOW_API_URL", "http://localhost:3001")
LEDGERFLOW_JWT_SECRET = ENV.fetch("LEDGERFLOW_JWT_SECRET", Rails.application.secret_key_base)
BUDGETFLOW_JWT_SECRET = ENV.fetch("BUDGETFLOW_JWT_SECRET", Rails.application.secret_key_base)

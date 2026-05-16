class Api::JwtService
  ALGORITHM = "HS256"
  EXPIRY    = 1.hour

  def self.encode(payload)
    JWT.encode(
      payload.merge(exp: EXPIRY.from_now.to_i, iss: "ledgerflow"),
      LEDGERFLOW_JWT_SECRET,
      ALGORITHM
    )
  end

  def self.decode(token, secret: BUDGETFLOW_JWT_SECRET)
    JWT.decode(token, secret, true, algorithm: ALGORITHM).first
  rescue JWT::DecodeError => e
    raise Api::AuthenticationError, e.message
  end
end

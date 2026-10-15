# B03c: the public keys of the certificates of this instance, at a fixed address (/.well-known/ledgerflow/keys.json): their identifier, their key, their fingerprint, their status.
# Nothing secret: a private key is never in the database.
class SigningKeysController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_second_factor!
  skip_before_action :set_current_entity
  skip_before_action :require_entity!

  def index
    expires_in 5.minutes, public: true
    render json: { "keys" => Ledger::SigningKeys.published }
  end
end

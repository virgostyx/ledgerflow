# Request context read by the audit trail (R18): who acted (a user, or the API client for third-party calls), from where, and the reason given for a correction.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :ip_address, :user_agent, :request_id, :reason, :api_client
end

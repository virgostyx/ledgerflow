# Request context read by the audit trail (R18): who acted, from where, and the reason given for a correction.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :ip_address, :user_agent, :request_id, :reason
end

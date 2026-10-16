# What a person from outside did. Each row is copied into the audit trail of the company (R18, actor_type portal_user) by an internal job; the portal itself writes nowhere else.
class Portal::Event < ApplicationRecord
  belongs_to :portal_user, optional: true

  # request: anything answering ip and user_agent (the portal's request, or nil).
  def self.record!(action, user: nil, entity_id: nil, target_token: nil, email_tried: nil, request: nil, **metadata)
    create!(action: action, portal_user: user, entity_id: entity_id, target_token: target_token, email_tried: email_tried.to_s.first(255).presence,
            ip_address: request&.remote_ip, user_agent: request&.user_agent.to_s.first(255).presence, metadata: metadata, occurred_at: Time.current)
  end
end

# The owner's acceptance of how the entity's data goes to the language model (A04). It is for one version of the text; when the text changes, the version changes, and the agent
# stays off for the entity until an owner accepts again.
class Agent::Consent < ApplicationRecord
  self.table_name = "agent_consents"

  # Bump it with the text in app/views/agent/settings/_consent.html.erb (a spec fails when the text changes and this does not).
  VERSION = "2026-10-06".freeze

  include Accounting::AuditTrailed

  acts_as_tenant :entity

  belongs_to :accepted_by, class_name: "User"

  validates :version, presence: true, uniqueness: { scope: :entity_id }

  def self.current? = exists?(version: VERSION)

  def self.accept!(user)
    find_or_create_by!(version: VERSION) { |consent| consent.accepted_by = user; consent.accepted_at = Time.current }
  end
end

# A summary of what deserves a person's attention (A10a), built for one person in one entity with their own rights and kept encrypted. Scheduled (their frequency) or triggered by an event (at most one per type
# and per day). Nothing in it is written by a model: the facts come from the read services and the sentences from templates. The e-mail carries counts and links; the figures and names stay in the application.
class Agent::Digest < ApplicationRecord
  self.table_name = "agent_digests"

  KINDS = %w[scheduled event].freeze
  EVENTS = %w[blocking_anomaly cash_below_threshold vat_due period_with_drafts].freeze
  MAX_ITEMS = 10

  acts_as_tenant :entity

  belongs_to :user

  encrypts :payload

  validates :kind, inclusion: { in: KINDS }
  validates :event_type, inclusion: { in: EVENTS }, if: -> { kind == "event" }
  validates :local_date, :payload, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :unread, -> { where(read_at: nil) }

  def data = @data ||= JSON.parse(payload)
  def sections = data.fetch("sections", [])
  def snapshot = data.fetch("snapshot", {})
  def read! = (update!(read_at: Time.current) unless read_at)
  def title = kind == "event" ? "Alert: #{event_type.to_s.tr('_', ' ')}" : "Summary of #{local_date.iso8601}"
end

# A text the assistant drafted for a person (A11): its versions, the facts it uses, what became of it. Encrypted. The assistant cannot send anything: the text goes out through the existing screens, by the person,
# and a reminder whose text it wrote is never sent by the automatic first level.
class Agent::TextDraft < ApplicationRecord
  self.table_name = "agent_text_drafts"

  KINDS = %w[dunning_letter client_request variation_comment summary reply_email rewrite].freeze
  THIRD_PARTY = %w[dunning_letter client_request reply_email].freeze # texts that leave the company: no internal note, no internal comment
  LANGUAGES = %w[fr nl en].freeze
  STATUSES = %w[draft used rejected].freeze
  MAX_VERSIONS = 20

  acts_as_tenant :entity

  belongs_to :user
  belongs_to :conversation, class_name: "Agent::Conversation", optional: true
  belongs_to :message, class_name: "Agent::Message", optional: true
  belongs_to :partner, class_name: "Accounting::Partner", optional: true

  encrypts :payload

  validates :kind, inclusion: { in: KINDS }
  validates :language, inclusion: { in: LANGUAGES }
  validates :status, inclusion: { in: STATUSES }
  validates :payload, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def data = payload.present? ? JSON.parse(payload) : {}
  def versions = data.fetch("versions", [])
  def current = versions.last || {}
  def subject_line = current["subject"]
  def body = current["body"].to_s
  def facts = data.fetch("facts", [])
  def warnings = data.fetch("warnings", [])
  def third_party? = THIRD_PARTY.include?(kind)
  def draft? = status == "draft"

  # A new version: what the model wrote after an instruction, or what the person typed. The older ones stay, for the differences.
  def add_version!(subject:, body:, by:, instruction: nil, facts: nil, warnings: nil)
    content = data
    content["versions"] = (versions + [ { "subject" => subject, "body" => body, "by" => by, "instruction" => instruction, "at" => Time.current.iso8601 } ]).last(MAX_VERSIONS)
    content["facts"] = facts if facts
    content["warnings"] = warnings if warnings
    update!(payload: content.to_json)
  end

  def first_proposed_body = versions.find { |version| version["by"] == "assistant" }&.dig("body").to_s

  # The person used the text: as it was proposed, or changed. The distance is between the first proposal and what they used.
  def use!(in_place, text)
    update!(status: "used", used_in: in_place, edit_distance: Agent::EditDistance.between(first_proposed_body, text), outcome: text.squish == first_proposed_body.squish ? "used_as_is" : "modified")
  end

  def reject! = update!(status: "rejected", outcome: "rejected")
end

# B02b: one bank line of a request, as the client may see it: a date, a cleaned label, an amount. Never the counterparty's IBAN, never the bank's references.
class Portal::DocumentRequestLine < ApplicationRecord
  REASONS = { "personal" => "No invoice: personal expense", "lost" => "Invoice lost: a copy is asked", "other" => "Other" }.freeze
  STATES = %w[open provided explained withdrawn].freeze

  belongs_to :request, class_name: "Portal::DocumentRequest", inverse_of: :lines
  belongs_to :answered_by, class_name: "PortalUser", optional: true

  has_secure_token :token
  validates :state, inclusion: { in: STATES }

  scope :open_ones, -> { where(state: "open") }

  # The lines a person may see: the companies where a right in force lists bank_lines.view and where the firm shows its bank lines (what is withdrawn stays visible, with its reason).
  def self.in_reach_of(person, capability: "bank_lines.view")
    where(entity_id: person.open_grants.where("portal_grants.capabilities @> ?", [ capability ].to_json).select(:entity_id))
      .where(entity_id: Portal::Company.where(show_bank_lines: true).select(:id))
  end

  def reason_label = REASONS[answer_reason.to_s]

  def to_param = token
end

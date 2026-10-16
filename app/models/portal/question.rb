# B02c: a question of the firm to the people of the portal, about something they know (an expense, a payment, a document). What the client reads is here; the task of the firm
# (F08) and the treatments suggested for each choice stay on the firm's side. The answer never changes the books.
class Portal::Question < ApplicationRecord
  ANSWER_TYPES = %w[text single multiple yes_no file amount date].freeze
  CHOICE_TYPES = %w[single multiple].freeze

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :portal_user, optional: true
  has_one :answer, class_name: "Portal::Answer", foreign_key: :question_id, inverse_of: :question

  has_secure_token :token
  enum :status, { open: "open", answered: "answered", closed: "closed", expired: "expired" }, default: "open"

  validates :title, presence: true
  validates :answer_type, inclusion: { in: ANSWER_TYPES }

  # What a person may answer: the companies where a right in force lists questions.answer and the feature is on, the questions addressed to everyone or to them.
  scope :in_reach_of, lambda { |person|
    entity_ids = person.open_grants.where("portal_grants.capabilities @> ?", [ "questions.answer" ].to_json).select(:entity_id)
    where(entity_id: Portal::Company.where(questions_enabled: true, id: entity_ids).select(:id)).where("portal_questions.portal_user_id IS NULL OR portal_questions.portal_user_id = ?", person.id)
  }

  def to_param = token
  def choice_keys = choices.map { |c| c["key"] }
  def choice_label(key) = choices.find { |c| c["key"] == key }&.fetch("label", nil)
end

# What a person thought of an answer (A01): useful or not, and when not, what was wrong. One opinion per person and message.
class Agent::Feedback < ApplicationRecord
  self.table_name = "agent_feedback"

  CATEGORIES = %w[wrong_figure off_topic incomplete too_long other].freeze

  belongs_to :message, class_name: "Agent::Message"
  belongs_to :user

  encrypts :comment

  enum :rating, { useful: "useful", not_useful: "not_useful" }

  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :user_id, uniqueness: { scope: :message_id }
end

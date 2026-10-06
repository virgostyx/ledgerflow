# A name or an identifier replaced by a token for the model, in one conversation (A04). The table is encrypted, belongs to the conversation, and is never sent to the model: it is
# what turns the tokens of an answer back into what the person knows. The value is encrypted so that the same value always gives the same ciphertext: that is what lets an owner
# find a person in the conversations.
class Agent::Pseudonym < ApplicationRecord
  self.table_name = "agent_pseudonyms"

  KINDS = %w[person tax_identifier].freeze

  belongs_to :conversation, class_name: "Agent::Conversation"

  encrypts :real_value, deterministic: true

  validates :token, :real_value, presence: true
  validates :kind, inclusion: { in: KINDS }
end

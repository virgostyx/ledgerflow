# A01: a conversation is "answering" from the moment a question is accepted to the end of the answer, so that a company cannot run more than a few generations at once
# (spec §16). A value older than a few minutes is a job that died and counts for nothing. Reversible.
class AddAnsweringSinceToAgentConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_conversations, :answering_since, :datetime
    add_index :agent_conversations, %i[entity_id answering_since], where: "answering_since IS NOT NULL"
  end
end

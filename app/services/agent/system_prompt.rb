# The system prompt (A01): the principles of the agent, kept in a file that the interface cannot change, then what the session knows: the entity, the day, the language,
# the screen and the object the panel was opened on (a reference, never copied text).
module Agent::SystemPrompt
  PRINCIPLES = Rails.root.join("app/services/agent/prompts/system.md")

  def self.build(context)
    <<~PROMPT
      #{PRINCIPLES.read.strip}

      Session
      - Entity: #{context.entity.name}
      - Today: #{context.today.iso8601}
      - Language of the person: #{context.locale}
      - Screen: #{context.screen.presence || 'none'}
      - Object open: #{context.subject_ref.presence ? context.subject_ref.to_json : 'none'}
    PROMPT
  end
end

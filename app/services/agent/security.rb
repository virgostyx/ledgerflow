# What the agent's defences record while it answers (A03): an event for the owners and a line in the audit trail each time a tool is refused, an argument is not allowed,
# a text looks like an instruction to an AI, or something is taken out of an answer. It also keeps the flags the answer will carry (a badge in the panel).
class Agent::Security
  REPEATED_AFTER = 3

  # A short extract, with what would identify someone or something taken out: an IBAN, an e-mail address, a long number.
  def self.mask_excerpt(text)
    text.to_s.squish.gsub(/\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){10,30}\b/, "[iban]").gsub(/[\w.+-]+@[\w-]+\.[\w.-]+/, "[email]").gsub(/\d{9,}/, "[number]").then { |masked| masked.length > 160 ? "#{masked[0, 159]}…" : masked }
  end

  attr_reader :flags

  def initialize(conversation:, context:)
    @conversation = conversation
    @context = context
    @flags = []
  end

  def event(kind, tool: nil, excerpt: nil)
    record = Agent::SecurityEvent.create!(entity: @context.entity, conversation: @conversation, user: @context.user, kind: kind.to_s, tool: tool, excerpt: (self.class.mask_excerpt(excerpt) if excerpt))
    Accounting::AuditLog.record!(auditable: record, action: "agent_security_event", user: @context.user, payload: { kind: kind.to_s, tool: tool }.compact)
    record
  end

  # A tool refused for lack of the right. The third time in a conversation is worth saying once more: someone is trying.
  def forbidden!(tool)
    event(:forbidden_tool, tool: tool)
    return unless @conversation && Agent::SecurityEvent.where(conversation: @conversation, kind: "forbidden_tool").count == REPEATED_AFTER

    event(:repeated_forbidden, tool: tool)
  end

  # Text that looks like an instruction to an AI was among the data. The message will carry a badge; nothing else changes.
  def suspicious!(tool, findings)
    flag("suspicious_content")
    findings.each { |finding| event(:suspicious_content, tool: tool, excerpt: "#{finding[:patterns].join(', ')}: #{finding[:excerpt]}") }
  end

  def flag(name) = (@flags << name unless @flags.include?(name))
end

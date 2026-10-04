# What a person does with a received message that waits (F06 step 4): work on it again, give it its supplier, put it aside. A message is never
# deleted and never posted by these: they only bring it back to the pipeline, or close it with a reason. Each one is audited.
module Peppol::MessageActions
  def self.reprocess(message:, user:)
    return failure(message, "Only a message that waits for review can be worked on again") unless message.needs_review? || message.received?

    work_on(message)
    Accounting::AuditLog.record!(auditable: message, action: "peppol_message_reprocessed", user: user, payload: { status: message.status, problems: message.problems })
    LightService::Context.make(message: message)
  end

  # The supplier a person picked (when several partners shared an identifier); the message is then worked on again.
  def self.assign_supplier(message:, partner:, user:)
    return failure(message, "Only a message that waits for review can be given a supplier") unless message.needs_review?

    message.update!(partner: partner)
    Accounting::AuditLog.record!(auditable: message, action: "peppol_supplier_chosen", user: user, payload: { partner_id: partner.id })
    reprocess(message: message, user: user)
  end

  def self.dismiss(message:, user:, reason:)
    return failure(message, "Only a message that waits for review can be put aside") unless message.needs_review?
    return failure(message, "Say why the message is put aside") if reason.to_s.strip.blank?

    message.update!(status: :dismissed, note: [ message.note, "Put aside: #{reason.strip}" ].compact.join(" · "))
    Accounting::AuditLog.record!(auditable: message, action: "peppol_message_dismissed", user: user, reason: reason.strip)
    LightService::Context.make(message: message)
  end

  # A document that was announced but never fetched is fetched first; a technical error is told, the message stays as it is.
  def self.work_on(message)
    return Peppol::ProcessMessage.call(message: message) if message.xml.present? || message.remote_id.blank?

    Peppol::FetchReceived.call(message: message)
  rescue Peppol::AccessPoint::TemporaryError => e
    message.update!(problems: [ "The Access Point cannot be reached: #{e.message}" ])
  end

  def self.failure(message, text) = LightService::Context.make(message: message).tap { |ctx| ctx.fail!(text) }
  private_class_method :work_on, :failure
end

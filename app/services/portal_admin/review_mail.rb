# B02b: a person of the firm looks at a mail that was put in quarantine: releasing it hands its attachments to the usual upload (nothing is trusted from it, it is parsed only now), discarding it
# keeps the raw message for the record. A mail is reviewed once.
class PortalAdmin::ReviewMail
  def self.release(item, by:)
    return fail_with("This mail was already reviewed.") unless item.pending?

    mail = Mail.new(item.raw)
    files = mail.attachments.reject { |a| a.inline? && a.content_type.to_s.start_with?("image/") && a.decoded.bytesize < DocumentsMailbox::SIGNATURE_IMAGE_BYTES }
                .map { |attachment| [ StringIO.new(attachment.decoded), attachment.filename.to_s ] }
    result = Accounting::UploadFiles.call(files: files, user: by, origin: :email, details: { source: { email: { from: item.sender, subject: item.subject, message_id: item.message_id, released_from_quarantine: item.id } } })
    ApplicationRecord.transaction do
      item.update!(status: "released", reviewed_by: by, reviewed_at: Time.current)
      Accounting::AuditLog.record!(auditable: item, action: "document_mail_released", user: by, payload: { sender: item.sender, created: result.created.size, refused: result.refused.size })
    end
    LightService::Context.make(item: item, created: result.created, refused: result.refused)
  end

  def self.discard(item, by:)
    return fail_with("This mail was already reviewed.") unless item.pending?

    ApplicationRecord.transaction do
      item.update!(status: "discarded", reviewed_by: by, reviewed_at: Time.current)
      Accounting::AuditLog.record!(auditable: item, action: "document_mail_discarded", user: by, payload: { sender: item.sender })
    end
    LightService::Context.make(item: item)
  end

  def self.fail_with(message) = LightService::Context.make.tap { |c| c.fail!(message) }
  private_class_method :fail_with
end

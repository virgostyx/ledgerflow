# Mail to an entity's secret address (documents+<secret>@<domain>) puts its attachments in the entity's document inbox
# (F03), each one an ordinary upload (checked, deduplicated, audited, read) that remembers who sent it. An archive is
# unpacked. A small inline image (a logo in a signature) is not a document. An address nobody has, or an entity that
# has not turned the feature on, gets no answer at all: nothing is created and a stranger learns nothing.
class DocumentsMailbox < ApplicationMailbox
  SIGNATURE_IMAGE_BYTES = 10.kilobytes
  ADDRESS = /\Adocuments\+(?<token>[0-9a-z]+)@/i

  def process
    entity = Entity.find_by("lower(documents_mail_token) = ?", token)
    return unless entity&.feature?(:f03)

    ActsAsTenant.with_tenant(entity) { entity.feature?(:b02b) ? screened_ingest : ingest }
  end

  private

  def token
    mail.recipients.compact.filter_map { |recipient| recipient.to_s.strip[ADDRESS, :token]&.downcase }.first
  end

  def ingest
    files = attachments.map { |attachment| [ StringIO.new(attachment.decoded), attachment.filename.to_s ] }
    return if files.empty?

    result = Accounting::UploadFiles.call(files: files, user: nil, origin: :email, details: { source: { email: source } })
    Rails.logger.info("[documents] mail #{mail.message_id}: #{result.created.size} documents created, #{result.refused.size} refused: #{result.refused.join(' | ')}")
    result
  end

  # B02b: with the portal's document upload on, the address is closed to strangers, and to whoever the receiving server did not vouch for: they wait in quarantine, unread.
  def screened_ingest
    reason = PortalAdmin::ScreenMail.call(entity: entity, mail: mail)
    return quarantine(reason) if reason

    result = ingest
    reply(result.created.size + result.refused.size) if result && !PortalAdmin::ScreenMail.automatic?(mail)
  end

  def entity = ActsAsTenant.current_tenant

  def quarantine(reason)
    item = Accounting::MailQuarantine.create!(sender: mail.from&.first.to_s.downcase.first(255), subject: mail.subject.to_s.first(200), message_id: mail.message_id.to_s.first(255), reason: reason,
                                              raw: mail.encoded, attachment_count: attachments.size)
    Accounting::AuditLog.record!(auditable: item, action: "document_mail_quarantined", payload: { sender: item.sender, reason: reason, attachments: item.attachment_count })
  end

  # Only to a sender we know and that passed: never to a stranger (it would be an answer to anyone who writes), never to a machine.
  def reply(count)
    DocumentsMailer.received(mail.from.first, count, mail.message_id).deliver_now if count.positive?
  rescue StandardError => e
    Rails.logger.error("[documents] receipt not sent: #{e.class}")
  end

  def attachments = mail.attachments.reject { |attachment| signature_image?(attachment) }

  def signature_image?(attachment)
    attachment.inline? && attachment.content_type.to_s.start_with?("image/") && attachment.decoded.bytesize < SIGNATURE_IMAGE_BYTES
  end

  def source = { from: mail.from&.first, subject: mail.subject.to_s.first(200), message_id: mail.message_id }
end

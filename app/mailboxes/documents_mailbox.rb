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

    ActsAsTenant.with_tenant(entity) { ingest }
  end

  private

  def token
    mail.recipients.compact.filter_map { |recipient| recipient.to_s.strip[ADDRESS, :token]&.downcase }.first
  end

  def ingest
    files = mail.attachments.reject { |attachment| signature_image?(attachment) }.map { |attachment| [ StringIO.new(attachment.decoded), attachment.filename.to_s ] }
    return if files.empty?

    result = Accounting::UploadFiles.call(files: files, user: nil, origin: :email, details: { source: { email: source } })
    Rails.logger.info("[documents] mail #{mail.message_id}: #{result.created.size} documents created, #{result.refused.size} refused: #{result.refused.join(' | ')}")
  end

  def signature_image?(attachment)
    attachment.inline? && attachment.content_type.to_s.start_with?("image/") && attachment.decoded.bytesize < SIGNATURE_IMAGE_BYTES
  end

  def source = { from: mail.from&.first, subject: mail.subject.to_s.first(200), message_id: mail.message_id }
end

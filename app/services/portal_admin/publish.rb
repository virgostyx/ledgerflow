# B02a: the firm publishes to the portal of a company. The right (portal.manage) is checked by the caller. The files are frozen with their SHA-256: given as bytes (the
# exporters of the reports) or taken from documents of the company (checked against the SHA-256 the document carries).
class PortalAdmin::Publish
  MAX_FILE_BYTES = 25.megabytes
  MAX_FILES = 10
  CONTENT_TYPES = %w[application/pdf image/png image/jpeg text/csv application/json application/vnd.openxmlformats-officedocument.spreadsheetml.sheet].freeze

  Refused = Class.new(StandardError)

  def self.call(entity:, kind:, title:, by:, files: [], documents: [], recipients: [], replaces: nil, message: nil, period: nil, requires_approval: false, approvers: [], approvals_required: "one", watermark: true, expires_at: nil, known_at: nil)
    result = LightService::Context.make
    raise Refused, "the client portal is not on for this company" unless entity.feature?(:b02a)

    parts = files.map { |f| f.slice(:filename, :content_type, :data) } + documents.map { |d| from_document(d, entity) }
    check_files!(parts)
    check_approvers!(entity, requires_approval, approvers, approvals_required)
    publication = nil
    ApplicationRecord.transaction do
      version = 1
      if replaces
        replaces.lock!
        raise Refused, "that publication belongs to another company" unless replaces.entity_id == entity.id
        raise Refused, "that publication already has a newer version" if replaces.replaced_by_id

        version = replaces.version + 1
      end
      publication = Portal::Publication.create!(
        entity_id: entity.id, kind: kind, title: title.to_s.strip, message: message.presence, published_by: by, published_at: Time.current, version: version, replaces: replaces,
        period_start: period&.first, period_end: period&.last, requires_approval: requires_approval, approvals_required: approvals_required, watermark: watermark, expires_at: expires_at, known_at: known_at, token: SecureRandom.urlsafe_base64(16)
      )
      parts.each_with_index do |part, position|
        publication.files.create!(token: SecureRandom.urlsafe_base64(16), filename: File.basename(part[:filename].to_s), content_type: part[:content_type], byte_size: part[:data].bytesize,
                                  sha256: Digest::SHA256.hexdigest(part[:data]), content: part[:data], position: position)
      end
      recipients.each { |person| publication.recipient_rows.create!(portal_user: person) }
      approvers.each { |person| publication.approver_rows.create!(portal_user: person) } if requires_approval
      if replaces
        replaces.update!(replaced_by: publication)
        replaces.approvals.active.update_all(status: "superseded", updated_at: Time.current) # what a person approved is not what is now published: they are asked again
      end
      ActsAsTenant.with_tenant(entity) do
        Accounting::AuditLog.record!(auditable: publication, action: "portal_published", user: by,
                                     payload: { kind: kind, title: publication.title, version: version, replaces_id: replaces&.id, requires_approval: requires_approval,
                                                recipients: recipients.map(&:id), files: publication.files.map { |f| { name: f.filename, sha256: f.sha256, bytes: f.byte_size } } })
      end
    end
    PortalAdmin::NotifyPublication.call(publication) # after the commit: nothing is told of a publication that was not kept
    result[:publication] = publication
    result
  rescue Refused, ActiveRecord::RecordInvalid => e
    LightService::Context.make.tap { |r| r.fail!(e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message) }
  end

  # Accounts to approve are approved by directors whose identity the firm checked: nobody else is named.
  def self.check_approvers!(entity, requires_approval, approvers, policy)
    return unless requires_approval

    raise Refused, "name at least one person who may approve" if approvers.empty?
    raise Refused, "choose whether one or all of them must approve" unless %w[one all].include?(policy.to_s)

    unqualified = approvers.reject { |person| person.qualified_approver_in?(entity.id) }
    raise Refused, "#{unqualified.map(&:full_name).join(', ')}: not a director with a verified identity and the right to approve" if unqualified.any?
  end

  def self.from_document(document, entity)
    raise Refused, "that document belongs to another company" unless document.entity_id == entity.id

    data = document.file.download
    raise Refused, "the file of #{document.name} does not match its SHA-256: it was not published" unless Digest::SHA256.hexdigest(data) == document.sha256

    { filename: document.name, content_type: document.content_type, data: data }
  end

  def self.check_files!(parts)
    raise Refused, "add at least one file" if parts.empty?
    raise Refused, "at most #{MAX_FILES} files in one publication" if parts.size > MAX_FILES

    parts.each do |part|
      raise Refused, "#{part[:filename]}: this type of file is not served by the portal" unless CONTENT_TYPES.include?(part[:content_type])
      raise Refused, "#{part[:filename]}: larger than #{MAX_FILE_BYTES / 1.megabyte} MB" if part[:data].bytesize > MAX_FILE_BYTES
    end
  end
  private_class_method :from_document, :check_files!, :check_approvers!
end

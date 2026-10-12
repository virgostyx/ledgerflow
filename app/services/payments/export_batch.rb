# Makes the payment file of an approved batch (B01b §5): the person loads it and authorizes it in their own bank, LedgerFlow initiates nothing.
# It asks for the right to export, a second factor given a moment ago, an approval that is of the batch as it is now, and a pre-flight that still holds (an account
# blocked, an invoice held or paid elsewhere since the approval stops the file). The file is kept as a document of the company, with its SHA-256; the batch is then frozen.
# => ctx[:file] (the bytes), ctx[:code] when refused
class Payments::ExportBatch
  def self.call(batch:, user:, recent_second_factor: false)
    ctx = LightService::Context.make(file: nil)
    code = refusal_for(batch, user, recent_second_factor)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id) # one export at a time
      next refuse(ctx, :not_approved) unless batch.reload.approved?

      report = Payments::Preflight.call(batch)
      next refuse(ctx, :preflight, report.errors.first&.message || I18n.t("payments.export.warnings_open")) unless report.ready?

      write(ctx, batch, user)
    end
    ctx
  rescue Payments::Sepa::UnsupportedVersion, SEPA::Error, ArgumentError => e
    refuse(ctx, :file_not_made, I18n.t("payments.export.file_not_made", message: e.message))
  end

  def self.refusal_for(batch, user, recent_second_factor)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :not_allowed unless Payments::BatchPolicy.new(user, batch).export?
    return :step_up_required unless recent_second_factor
    return :not_approved unless batch.approved? && batch.approval_request&.approved?
    return :no_profile unless batch.bank_profile

    :content_changed unless batch.approval_request.content_fingerprint == Approvals::ContentFingerprint.call(batch)
  end
  private_class_method :refusal_for

  def self.write(ctx, batch, user)
    now = Time.current
    batch.update!(message_id: batch.reference, format_version: batch.bank_profile.format_version) # what the builder reads
    file = Payments::Sepa::Pain001Builder.call(batch, created_at: now)
    sha256 = Digest::SHA256.hexdigest(file)
    document = Accounting::Document.new(name: "#{batch.reference}.xml", content_type: "application/xml", byte_size: file.bytesize, sha256: sha256, origin: :payment_file, kind: :other, uploaded_by: user)
    document.file.attach(io: StringIO.new(file), filename: "#{batch.reference}.xml", content_type: "application/xml")
    document.save!
    batch.update!(status: :exported, document: document, file_sha256: sha256, control_sum: batch.total, exported_by: user, exported_at: now)
    Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_exported", user: user,
                                 payload: { sha256: sha256, payments: batch.payments_count, total: format("%.2f", batch.total), message_id: batch.message_id, format_version: batch.format_version, document_id: document.id })
    ctx[:file] = file
  end
  private_class_method :write

  def self.refuse(ctx, code, message = nil)
    ctx[:code] = code
    ctx.fail!(message || I18n.t("payments.export.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end

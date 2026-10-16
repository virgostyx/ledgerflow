# B02b: copies, to the portal's own table, where the document of each upload stands in the firm, in the four words a client may be told: received (in the inbox, untouched),
# in progress (linked to something), booked (linked to a validated entry), to complete (a question is open about it). Nothing more leaves the books. A change to "to complete" tells the client once.
class PortalAdmin::SyncUploadProgress
  QUESTIONS = %i[missing_document client_question].freeze

  def self.call
    Portal::Upload.accepted.where.not(progress: "booked").includes(:portal_user).group_by(&:entity_id).each do |entity_id, uploads|
      ActsAsTenant.with_tenant(Entity.find(entity_id)) { sync(entity_id, uploads) }
    end
  end

  def self.sync(entity_id, uploads)
    ids = uploads.filter_map(&:document_id)
    documents = Accounting::Document.where(id: ids).index_by(&:id)
    questions = Accounting::Task.open_ones.where(kind: QUESTIONS.map { |k| Accounting::Task.kinds.fetch(k) }, target_type: "Accounting::Document", target_id: ids).pluck(:target_id)
    booked = Accounting::DocumentLink.where(document_id: ids, target_type: "Accounting::JournalEntry")
                                     .where(target_id: Accounting::JournalEntry.where.not(status: :draft).select(:id)).distinct.pluck(:document_id)
    uploads.each do |upload|
      document = documents[upload.document_id] or next
      progress = if questions.include?(document.id) then "to_complete"
      elsif booked.include?(document.id) then "booked"
      elsif document.inbox? then "received"
      else "in_progress"
      end
      change(upload, progress, entity_id)
    end
  end

  def self.change(upload, progress, entity_id)
    return if upload.progress == progress

    upload.update!(progress: progress)
    PortalAdmin::NotifyUpload.call(upload) if progress == "to_complete"
  end
  private_class_method :sync, :change
end

# B02b: a document that came to the wrong company is moved to the right one by the team. Only by someone who may upload documents in both, only while the document is untouched (still in the
# inbox, no link, no task, no comment, not cut from or into another, no legal hold), and only if the other company does not already have the same file. Both audit chains tell it.
class PortalAdmin::MoveDocument
  def self.call(document:, to:, by:)
    from = document.entity
    return fail_with("The document is already in this company.") if from.id == to.id
    return fail_with("You do not work in both companies.") unless works_in?(by, from) && works_in?(by, to)

    problem = ActsAsTenant.with_tenant(from) { in_use(document) }
    return fail_with(problem) if problem
    return fail_with("The other company already has this file.") if ActsAsTenant.with_tenant(to) { Accounting::Document.exists?(sha256: document.sha256) }

    ApplicationRecord.transaction do
      ActsAsTenant.with_tenant(from) { Accounting::AuditLog.record!(auditable: document, action: "document_moved_out", user: by, payload: { to_entity_id: to.id, name: document.name }) }
      document.update_columns(entity_id: to.id, updated_at: Time.current) # the entity is the scope of the document: no validation, no callback applies to a move
      ActsAsTenant.with_tenant(to) { Accounting::AuditLog.record!(auditable: document, action: "document_moved_in", user: by, payload: { from_entity_id: from.id, name: document.name }) }
    end
    LightService::Context.make(document: document)
  end

  def self.works_in?(user, entity) = UserEntity.current.find_by(user: user, entity: entity)&.allows?("documents.upload") == true

  def self.in_use(document)
    return "The document is not in the inbox any more." unless document.inbox?
    return "The document is under a legal hold." if document.legal_hold
    return "The document is linked to something." if document.links.exists?
    return "A task or a comment is about this document." if Accounting::Task.about(document).exists? || Accounting::Comment.where(commentable: document).exists?
    "The document was cut from or into another." if document.parent_id || document.children.exists? || document.replaces_id
  end

  def self.fail_with(message) = LightService::Context.make(document: nil).tap { |c| c.fail!(message) }
  private_class_method :works_in?, :in_use, :fail_with
end

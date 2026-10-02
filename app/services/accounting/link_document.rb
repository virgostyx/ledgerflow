# Attaches a document to what it justifies (an entry, a partner, an asset, an invoice, a bank transaction).
# The target must belong to the document's entity. A linked document leaves the inbox.
class Accounting::LinkDocument
  def self.call(document:, target:, user:)
    ctx = LightService::Context.make(link: nil)
    return fail_with(ctx, "documents.errors.archived") if document.archived?
    return fail_with(ctx, "documents.errors.bad_target") unless valid_target?(document, target)

    link = document.links.build(target: target, created_by: user)
    ApplicationRecord.transaction do
      link.save!
      document.update!(status: :linked) if document.inbox?
      Accounting::AuditLog.record!(auditable: document, action: "document_link", user: user,
                                   payload: { target_type: target.class.name, target_id: target.id })
    end
    ctx[:link] = link
    ctx
  rescue ActiveRecord::RecordInvalid
    fail_with(ctx, "documents.errors.already_linked")
  end

  def self.valid_target?(document, target)
    Accounting::DocumentLink::TARGET_TYPES.include?(target.class.name) && target.try(:entity_id) == document.entity_id
  end

  def self.fail_with(ctx, key) = ctx.tap { |c| c.fail!(I18n.t(key)) }

  private_class_method :valid_target?, :fail_with
end

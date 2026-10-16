# B02b: the round that follows the requests for supporting documents, every few minutes. A line the firm justified itself is withdrawn from the client, with a message; a line whose document
# came from the client is provided; an answer without a document becomes one task for the accountant (once), and nothing is booked.
class PortalAdmin::SyncDocumentRequests
  REASONS = { "personal" => "no invoice (personal expense)", "lost" => "invoice lost, copy asked", "other" => "other reason" }.freeze

  def self.call
    Portal::DocumentRequestLine.where(state: %w[open explained]).group_by(&:entity_id).each do |entity_id, lines|
      ActsAsTenant.with_tenant(Entity.find(entity_id)) { lines.each { |line| sync(line) } }
    end
  end

  def self.sync(line)
    transaction = Accounting::BankTransaction.find_by(id: line.bank_transaction_id)
    return unless transaction

    line.state == "open" ? follow_documents(line, transaction) : open_task(line, transaction)
  end

  def self.follow_documents(line, transaction)
    documents = Accounting::DocumentLink.where(target_type: "Accounting::BankTransaction", target_id: transaction.id).pluck(:document_id)
    return if documents.empty?

    if Portal::Upload.exists?(request_line_id: line.id, document_id: documents)
      line.update!(state: "provided")
    else
      line.update!(state: "withdrawn", withdrawn_reason: "This line was justified by your accountant.")
      Accounting::AuditLog.record!(auditable: line.request, action: "portal_document_request_withdrawn", payload: { line: line.token, bank_transaction_id: transaction.id })
    end
  end

  def self.open_task(line, transaction)
    return if line.task_id

    ApplicationRecord.transaction do
      task = Accounting::Task.create!(title: "Client answer: #{REASONS.fetch(line.answer_reason.to_s, 'other reason')}", kind: :missing_document, target: transaction,
                                      description: "#{line.answered_by&.full_name} answered without a document for the line of #{line.line_date} (#{line.amount} #{line.currency}).#{" Note: #{line.answer_note}" if line.answer_note.present?}")
      line.update!(task_id: task.id)
      Accounting::AuditLog.record!(auditable: task, action: "portal_document_request_answered", payload: { reason: line.answer_reason, line: line.token, portal_user_id: line.answered_by_id })
    end
  end
  private_class_method :sync, :follow_documents, :open_task
end

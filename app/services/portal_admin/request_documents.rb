# B02b: the firm asks the clients of a company for the supporting documents of some bank lines. Only pending lines without a document, not already asked. What the client can see of a line
# is copied here (date, cleaned label, amount); nothing is booked. The clients who may see bank lines are told that something is asked, not what.
class PortalAdmin::RequestDocuments
  def self.call(entity:, lines:, by:, message: nil, due_on: nil)
    context = LightService::Context.make(request: nil)
    return fail_with(context, "The client portal does not take documents for this company.") unless entity.feature?(:b02a) && entity.feature?(:b02b)
    return fail_with(context, "Bank lines are not shown to the clients of this company.") unless entity.portal_show_bank_lines?

    lines = Array(lines)
    return fail_with(context, "Choose at least one bank line.") if lines.empty?

    recipients = people(entity)
    return fail_with(context, "Nobody of the client portal may see bank lines yet.") if recipients.empty?

    refused = lines.reject { |line| askable?(line, entity) }
    return fail_with(context, "These lines cannot be asked for: #{refused.map { |l| "#{l.transaction_date} #{l.amount}" }.join(', ')}.") if refused.any?

    request = ApplicationRecord.transaction do
      Portal::DocumentRequest.create!(entity_id: entity.id, message: message.to_s.strip.first(1000).presence, due_on: due_on.presence, requested_by: by).tap do |created|
        lines.each do |line|
          created.lines.create!(entity_id: entity.id, bank_transaction_id: line.id, line_date: line.transaction_date, label: PortalAdmin::BankLineLabel.call(line), amount: line.amount, currency: line.currency)
        end
        Accounting::AuditLog.record!(auditable: created, action: "portal_documents_requested", user: by, payload: { lines: lines.size, due_on: due_on.presence })
      end
    end
    recipients.each { |person| notify(person, entity, lines.size) }
    context[:request] = request
    context
  end

  # Whoever has a right in force that lists bank_lines.view in this company, and is active.
  def self.people(entity)
    granted = Portal::Grant.in_force.where(entity_id: entity.id).where("capabilities @> ?", [ "bank_lines.view" ].to_json).select(:portal_user_id)
    PortalUser.active.where(id: granted).to_a
  end

  def self.askable?(line, entity)
    line.entity_id == entity.id && line.pending? &&
      !Accounting::DocumentLink.exists?(target_type: "Accounting::BankTransaction", target_id: line.id) &&
      !Portal::DocumentRequestLine.open_ones.exists?(bank_transaction_id: line.id)
  end

  def self.notify(person, entity, count)
    return if person.notification_frequency == "off"

    Portal::NotificationMailer.documents_requested(person, entity.name, count).deliver_now
  rescue StandardError => e
    Rails.logger.error("portal notification not sent: #{e.class}")
  end

  def self.fail_with(context, message) = context.tap { |c| c.fail!(message) }
  private_class_method :askable?, :notify, :fail_with
end

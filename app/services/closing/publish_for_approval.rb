# B02c: publishes the balance sheet and the income statement of the year to the client portal, for the client's approval (the button of the closing assistant). The publication carries the period of
# the fiscal year, so that, with `client_approval_required`, step 18 of the closing waits for the approval. The approvers must be directors whose identity the firm checked (PortalAdmin::Publish
# refuses anyone else). Nothing is validated, closed or changed in the books.
class Closing::PublishForApproval
  def self.call(run:, user:, approvers:, approvals_required: "one", message: nil)
    year = run.fiscal_year
    entity = run.entity
    return fail_with("Open the closing first: this run is not open any more.") unless run.draft? || run.in_progress? || run.ready?
    return fail_with("The client portal is not on for this company.") unless entity.feature?(:b02a) && entity.feature?(:b02c)

    files = Accounting::ClosingBundle.new(year).client_pdfs.map { |name, data| { filename: name, content_type: "application/pdf", data: data } }
    previous = Portal::Publication.visible.where(entity_id: entity.id, requires_approval: true, kind: "situation").where("period_start = ? AND period_end = ?", year.start_date, year.end_date).first
    result = PortalAdmin::Publish.call(entity: entity, kind: "situation", title: "Annual accounts #{year.year}", message: message.presence, files: files, by: user, requires_approval: true, approvers: approvers,
                                      approvals_required: approvals_required, period: (year.start_date..year.end_date), replaces: previous)
    return fail_with(result.message) if result.failure?

    Accounting::AuditLog.record!(auditable: run, action: "closing_published_for_approval", user: user, payload: { fiscal_year: year.year, publication: result[:publication].token, replaces: previous&.token })
    result
  end

  def self.fail_with(message) = LightService::Context.make(publication: nil).tap { |c| c.fail!(message) }
  private_class_method :fail_with
end

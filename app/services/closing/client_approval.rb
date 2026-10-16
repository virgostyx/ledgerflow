# B02c: with `client_approval_required`, the closing (step 18) waits for the client's validation of the accounts of the year: a publication of the company that asked for approval, covers the
# fiscal year, is the current version and is approved (PortalAdmin::ApprovalStatus). Without the option, nothing is asked.
class Closing::ClientApproval
  def self.required?(entity) = entity.client_approval_required?

  def self.satisfied?(fiscal_year)
    Portal::Publication.visible.where(entity_id: fiscal_year.entity_id, requires_approval: true)
                       .where("period_start <= ? AND period_end >= ?", fiscal_year.start_date, fiscal_year.end_date)
                       .any? { |publication| PortalAdmin::ApprovalStatus.call(publication)[:state] == :approved }
  end
end

# R18 audit-trail report: filterable list, chain status, and a field-by-field before/after viewer.
class Accounting::AuditLogsController < ApplicationController
  CHAIN_AUTO_VERIFY_LIMIT = 5_000

  def index
    authorize Accounting::AuditLog
    @pagy, @logs = pagy(Accounting::AuditLogsQuery.new(params).call)
    @options = Accounting::AuditLogsQuery.filter_options
    total = Accounting::AuditLog.where(entity_id: ActsAsTenant.current_tenant.id).where.not(content_hash: nil).count
    @chain = Accounting::AuditVerifier.call(entity: ActsAsTenant.current_tenant) if params[:verify] == "1" || total <= CHAIN_AUTO_VERIFY_LIMIT
    @chain_size = total
  end

  def show
    @log = Accounting::AuditLog.find(params[:id])
    authorize @log
    @changes = @log.payload.is_a?(Hash) ? @log.payload["changes"] : nil
  end
end

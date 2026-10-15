# B03c: the page "Integrity": the last anchor, the last checks, the keys in force, the certificates issued, and the form to issue one. The authority of timestamps and the
# defaults are the owner's.
class Accounting::IntegrityController < ApplicationController
  before_action -> { require_feature!(:b03c) }

  def index
    authorize Integrity::CertificatePolicy, :index?, policy_class: Integrity::CertificatePolicy
    @anchor = Ledger::Anchor.chronological.last
    @anchors = Ledger::Anchor.chronological.reverse_order.limit(30)
    @runs = IntegrityCheckRun.recent.limit(5)
    @keys = Ledger::SigningKeys.published
    @certificates = IntegrityCertificate.recent.limit(50)
    @invariants = Integrity::Invariants.call if params[:invariants] == "1"
    @can_issue = certificate_policy.create?
    @can_configure = certificate_policy.configure?
    @fiscal_years = Accounting::FiscalYear.order(:start_date)
    @entity = ActsAsTenant.current_tenant
  end

  def settings
    authorize Integrity::CertificatePolicy, :configure?, policy_class: Integrity::CertificatePolicy
    entity = ActsAsTenant.current_tenant
    if entity.update(settings_params)
      %w[timestamp_authority_url timestamp_authority_ca integrity_default_disclosure integrity_public_company_name].each do |option|
        next unless (change = entity.saved_changes[option])

        # the certificate of an authority is public, but long: its fingerprint is what the trail keeps
        shown = ->(v) { option == "timestamp_authority_ca" ? v.presence && Digest::SHA256.hexdigest(v) : v }
        Accounting::AuditLog.record!(auditable: entity, action: "integrity_option_changed", user: current_user, payload: { option: option, from: shown.(change.first), to: shown.(change.last) })
      end
      redirect_to accounting_integrity_path, notice: t("integrity.settings_saved")
    else
      redirect_to accounting_integrity_path, alert: entity.errors.full_messages.to_sentence
    end
  end

  # The full check of the books, now: every entry recomputed.
  def check
    authorize Integrity::CertificatePolicy, :create?, policy_class: Integrity::CertificatePolicy
    result = Integrity::SelfCheck.run_for(ActsAsTenant.current_tenant, mode: :full)
    redirect_to accounting_integrity_path, (result.intact? ? { notice: t("integrity.check_clean", count: result.entries_checked) } : { alert: t("integrity.check_found", count: result.findings.size) })
  end

  private

  def certificate_policy = Integrity::CertificatePolicy.new(current_user, :certificate)

  def settings_params
    attrs = params.require(:entity).permit(:timestamp_authority_url, :timestamp_authority_ca, :integrity_default_disclosure, :integrity_public_company_name)
    attrs[:timestamp_authority_url] = attrs[:timestamp_authority_url].to_s.strip.presence
    attrs[:timestamp_authority_ca] = attrs[:timestamp_authority_ca].to_s.strip.presence
    attrs
  end
end

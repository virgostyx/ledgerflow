# B03c: issuing, reading, downloading, revoking and verifying again the certificates of integrity. Issuing asks for a second factor given a moment ago; the package of a
# certificate of the full level is built at the download, so that its passphrase is never kept.
class Accounting::IntegrityCertificatesController < ApplicationController
  before_action -> { require_feature!(:b03c) }
  before_action(only: :create) { require_recent_second_factor! }
  before_action :set_certificate, only: %i[show download package revoke verify]

  def create
    authorize Integrity::CertificatePolicy, :create?, policy_class: Integrity::CertificatePolicy
    result = Integrity::IssueCertificate.call(user: current_user, recent_second_factor: recent_second_factor?, disclosure: params[:disclosure], recipient: params[:recipient],
                                              fiscal_year: params[:fiscal_year_id].presence && Accounting::FiscalYear.find(params[:fiscal_year_id]),
                                              anchor_number: params[:covered].presence && params[:covered] != "now" ? params[:covered].to_i : nil)
    if result.success?
      redirect_to accounting_integrity_certificate_path(result[:certificate]), notice: t("integrity.issued")
    else
      redirect_to accounting_integrity_path, alert: result.message
    end
  end

  def show
    authorize Integrity::CertificatePolicy, :show?, policy_class: Integrity::CertificatePolicy
    @document = @certificate.payload_hash
    @verification = Integrity::VerifyCertificate.call(@certificate) if params[:verified] == "1"
    @can_issue = Integrity::CertificatePolicy.new(current_user, :certificate).revoke?
  end

  # The certificate (JSON, signed) or to be read (PDF).
  def download
    authorize Integrity::CertificatePolicy, :download?, policy_class: Integrity::CertificatePolicy
    record_download(params[:kind])
    case params[:kind]
    when "pdf" then send_data Integrity::CertificatePdf.call(@certificate, base_url: request.base_url), filename: "certificate-#{@certificate.uuid}.pdf", type: "application/pdf"
    else send_data JSON.pretty_generate(@certificate.to_document), filename: "certificate-#{@certificate.uuid}.json", type: "application/json"
    end
  end

  def package
    authorize Integrity::CertificatePolicy, :download?, policy_class: Integrity::CertificatePolicy
    return redirect_to(accounting_integrity_certificate_path(@certificate), alert: t("integrity.no_package")) unless @certificate.disclosure_level == "full"

    record_download("package")
    built = Integrity::BuildPackage.call(certificate: @certificate, passphrase: params[:passphrase])
    send_data built.data, filename: built.filename, type: "application/octet-stream"
  end

  def revoke
    authorize Integrity::CertificatePolicy, :revoke?, policy_class: Integrity::CertificatePolicy
    result = Integrity::RevokeCertificate.call(certificate: @certificate, user: current_user, reason: params[:reason].to_s.strip)
    redirect_to accounting_integrity_certificate_path(@certificate), (result.success? ? { notice: t("integrity.revoked") } : { alert: result.message })
  end

  def verify
    authorize Integrity::CertificatePolicy, :verify?, policy_class: Integrity::CertificatePolicy
    redirect_to accounting_integrity_certificate_path(@certificate, verified: 1)
  end

  private

  def set_certificate = @certificate = IntegrityCertificate.find_by!(uuid: params[:uuid])

  def record_download(kind)
    Accounting::AuditLog.record!(auditable: @certificate, action: "integrity_certificate_downloaded", user: current_user, payload: { uuid: @certificate.uuid, kind: kind.presence || "json" })
  end
end

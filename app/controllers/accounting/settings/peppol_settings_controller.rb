class Accounting::Settings::PeppolSettingsController < Accounting::Settings::BaseController
  before_action :set_entity

  def edit; end

  def update
    @entity.assign_attributes(entity_params)
    @entity.peppol_credentials = merged_credentials

    if @entity.save
      redirect_to edit_accounting_settings_peppol_settings_path, notice: t("accounting.settings.peppol_settings.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Development aid: plays an incoming invoice, as a real Access Point would deliver one.
  def simulate_incoming
    return redirect_to(edit_accounting_settings_peppol_settings_path, alert: t("accounting.settings.peppol_settings.simulator_only")) unless @entity.peppol_ap_simulator?

    result = Peppol::AccessPoint.for(@entity).simulate_incoming
    if result.failure?
      redirect_to edit_accounting_settings_peppol_settings_path, alert: result.message
    else
      redirect_to edit_accounting_settings_peppol_settings_path, notice: t("accounting.settings.peppol_settings.simulated")
    end
  rescue Peppol::AccessPoint::Error => e
    redirect_to edit_accounting_settings_peppol_settings_path, alert: e.message
  end

  private

  def set_entity
    @entity = ActsAsTenant.current_tenant
  end

  def entity_params
    params.require(:entity).permit(:peppol_access_point, :peppol_participant_id)
  end

  # Only the fields of the chosen provider are kept. A secret is never shown again, so an empty field keeps its stored value.
  def merged_credentials
    return {} unless @entity.peppol_access_point

    submitted = params.fetch(:credentials, {})
    Peppol::AccessPoint.credential_fields(@entity.peppol_access_point).to_h do |field|
      key = field[:key]
      [ key, submitted[key].presence || @entity.peppol_credentials_was.to_h[key] ]
    end.compact
  end
end

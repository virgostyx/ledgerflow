class Accounting::Settings::VatSettingsController < Accounting::Settings::BaseController
  def edit
    @entity = ActsAsTenant.current_tenant
  end

  def update
    @entity = ActsAsTenant.current_tenant

    if @entity.update(entity_params)
      redirect_to edit_accounting_settings_vat_settings_path, notice: t("accounting.settings.vat_settings.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def entity_params
    params.require(:entity).permit(:vat_filing_frequency, :vat_regime, :vat_scheme, :vat_prorata_rate)
  end
end

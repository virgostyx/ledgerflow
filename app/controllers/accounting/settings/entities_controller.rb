class Accounting::Settings::EntitiesController < Accounting::Settings::BaseController
  def edit
    @entity = ActsAsTenant.current_tenant
  end

  def update
    @entity = ActsAsTenant.current_tenant

    if @entity.update(entity_params)
      redirect_to edit_accounting_settings_entity_path, notice: t("accounting.settings.entity.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def entity_params
    allowed = %i[name legal_name legal_form vat_number country address_line1 address_line2 zip_code city]
    # the BudgetFlow declaration and the four-eyes rule are the owner's call
    allowed.push(:budgetflow_enabled, :four_eyes, :four_eyes_threshold, :read_only_export, features: Entity::FEATURES.map(&:to_sym)) if Accounting::Settings::BasePolicy.new(current_user, :settings).destroy?
    params.require(:entity).permit(*allowed)
  end
end

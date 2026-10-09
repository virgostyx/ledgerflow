class Accounting::Settings::EntitiesController < Accounting::Settings::BaseController
  def edit
    @entity = ActsAsTenant.current_tenant
  end

  def update
    @entity = ActsAsTenant.current_tenant

    if @entity.update(entity_params)
      audit_approval_options
      redirect_to edit_accounting_settings_entity_path, notice: t("accounting.settings.entity.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # The address is a secret: replacing it cuts off whoever had it (the old one stops working at once).
  def regenerate_documents_address
    @entity = ActsAsTenant.current_tenant
    return redirect_to(accounting_root_path, alert: t("errors.not_authorized")) unless Accounting::Settings::BasePolicy.new(current_user, :settings).destroy? && @entity.feature?(:f03)

    @entity.regenerate_documents_mail_token
    Accounting::AuditLog.record!(auditable: @entity, action: "documents_address_regenerated", user: current_user)
    redirect_to edit_accounting_settings_entity_path, notice: t("accounting.settings.entity.documents_address_regenerated")
  end

  # F02: the two accounts for the rounding differences of bank payments, on an entity that predates them (the owner's call).
  def create_rounding_accounts
    result = Accounting::CreateRoundingAccounts.call(user: current_user)
    return redirect_to(accounting_root_path, alert: result.message) if result.failure?

    redirect_to edit_accounting_settings_entity_path, notice: t("accounting.settings.entity.rounding_accounts_created", count: result[:created].size)
  end

  private

  # A waiver of the separation of tasks, or a change of the bulk threshold, is the owner's explicit and recorded choice (B01a).
  def audit_approval_options
    %w[bap_before_posting allow_self_approval bulk_threshold].each do |option|
      next unless (change = @entity.saved_changes[option])

      Accounting::AuditLog.record!(auditable: @entity, action: "approval_option_changed", user: current_user,
                                   payload: { option: option, from: change.first&.then { |v| v.is_a?(BigDecimal) ? v.to_s("F") : v }, to: change.last&.then { |v| v.is_a?(BigDecimal) ? v.to_s("F") : v } })
    end
  end

  def entity_params
    allowed = %i[name legal_name legal_form vat_number country address_line1 address_line2 zip_code city]
    # the BudgetFlow declaration and the four-eyes rule are the owner's call
    allowed.push(:budgetflow_enabled, :four_eyes, :four_eyes_threshold, :read_only_export, :auto_post_exact_bank_matches, :auto_reconcile_exact, :bank_rounding_tolerance, :bap_before_posting, :allow_self_approval, :bulk_threshold, features: Entity::FEATURES.map(&:to_sym)) if Accounting::Settings::BasePolicy.new(current_user, :settings).destroy?
    params.require(:entity).permit(*allowed)
  end
end

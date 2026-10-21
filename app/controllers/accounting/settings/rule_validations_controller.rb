# The owner records that an accountant has validated a rule set (VAT declaration, annual accounts). Audited.
class Accounting::Settings::RuleValidationsController < Accounting::Settings::BaseController
  before_action :authorize_owner!

  def index
    @validations = Accounting::RuleValidation.order(validated_on: :desc, id: :desc)
    @validation = Accounting::RuleValidation.new(validated_on: Date.current)
  end

  def create
    @validation = Accounting::RuleValidation.new(validation_params)
    if @validation.save
      Accounting::AuditLog.record!(auditable: @validation, action: "rule_validated", user: current_user,
                                   payload: @validation.slice(:rule_key, :validated_by_name, :validated_by_title, :validated_on, :reference))
      redirect_to accounting_settings_rule_validations_path, notice: "Validation recorded."
    else
      @validations = Accounting::RuleValidation.order(validated_on: :desc, id: :desc)
      render :index, status: :unprocessable_content
    end
  end

  def revoke
    validation = Accounting::RuleValidation.in_force.find(params[:id])
    validation.revoke!
    Accounting::AuditLog.record!(auditable: validation, action: "rule_validation_revoked", user: current_user,
                                 payload: validation.slice(:rule_key, :reference))
    redirect_to accounting_settings_rule_validations_path, notice: "Validation revoked."
  end

  private

  def authorize_owner!
    return if Accounting::Settings::BasePolicy.new(current_user, :settings).destroy?

    redirect_to accounting_root_path, alert: t("errors.not_authorized")
  end

  def validation_params
    params.require(:rule_validation).permit(:rule_key, :validated_by_name, :validated_by_title, :validated_on, :reference, :note)
  end
end

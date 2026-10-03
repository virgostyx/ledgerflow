# F02: the entity's rules for bank lines (made from a line of the reconciliation screen): see them, switch one off, delete one.
class Accounting::Settings::BankRulesController < Accounting::Settings::BaseController
  before_action { require_feature!(:f02) }

  def index
    @rules = Accounting::BankRule.by_priority.includes(:account, :partner)
  end

  def update
    rule = Accounting::BankRule.find(params[:id])
    if rule.update(params.require(:bank_rule).permit(:active, :priority, :score, :action))
      redirect_to accounting_settings_bank_rules_path, notice: t("accounting.settings.bank_rules.updated")
    else
      redirect_to accounting_settings_bank_rules_path, alert: rule.errors.full_messages.to_sentence
    end
  end

  def destroy
    Accounting::BankRule.find(params[:id]).destroy!
    redirect_to accounting_settings_bank_rules_path, notice: t("accounting.settings.bank_rules.deleted")
  end
end

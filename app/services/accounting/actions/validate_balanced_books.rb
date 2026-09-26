# A fiscal year cannot be closed while its balance sheet does not balance and no account explains it (see
# Accounting::ClosingChecklist, which also warns about the accounts that fit no heading).
class Accounting::Actions::ValidateBalancedBooks
  extend LightService::Action

  expects :fiscal_year

  executed do |ctx|
    check = Accounting::ClosingChecklist.new(fiscal_year: ctx.fiscal_year).call.checks.find { |c| c.key == :balance }
    if check.status == :blocking
      ctx.fail!(I18n.t("accounting.fiscal_years.errors.unbalanced", amount: Accounting::MoneyPresenter.new(check.amount.abs).format))
    end
  end
end

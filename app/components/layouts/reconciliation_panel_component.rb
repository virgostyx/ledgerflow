class Layouts::ReconciliationPanelComponent < ViewComponent::Base
  def initialize(transactions:, account_label:)
    @transactions  = transactions
    @account_label = account_label
  end

  def formatted_amount(amount)
    Accounting::MoneyPresenter.new(amount.abs).format
  end
end

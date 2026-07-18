class Accounting::AccountSelectComponent < ViewComponent::Base
  def initialize(accounts:, name:, selected: nil, prompt: nil, label: nil, disabled: false)
    @accounts = accounts
    @name     = name
    @selected = selected
    @prompt   = prompt
    @label    = label
    @disabled = disabled
  end

  def account_option_label(account)
    Accounting::AccountPresenter.new(account).option_label
  end
end

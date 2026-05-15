class Accounting::AccountPresenter
  def initialize(account)
    @account = account
  end

  def full_label
    "#{@account.code} — #{@account.label_fr}"
  end

  def option_label
    full_label
  end
end

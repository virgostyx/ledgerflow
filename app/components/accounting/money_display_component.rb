class Accounting::MoneyDisplayComponent < ViewComponent::Base
  def initialize(amount:, currency: "EUR", show_sign: false)
    @presenter = Accounting::MoneyPresenter.new(amount, currency: currency)
    @show_sign = show_sign
  end

  def formatted
    @show_sign ? @presenter.format_signed : @presenter.format
  end

  def css_class
    @presenter.css_class
  end
end

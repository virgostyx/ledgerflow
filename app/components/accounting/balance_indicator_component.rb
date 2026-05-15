class Accounting::BalanceIndicatorComponent < ViewComponent::Base
  def initialize(entry:)
    @entry = entry
  end

  def total_debit
    @total_debit ||= @entry.lines.sum(:debit)
  end

  def total_credit
    @total_credit ||= @entry.lines.sum(:credit)
  end

  def balanced?
    (total_debit - total_credit).abs <= BigDecimal("0.01")
  end

  def balance_css_class
    balanced? ? "text-emerald-600" : "text-red-600"
  end
end

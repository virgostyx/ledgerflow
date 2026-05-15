class Layouts::TrialBalanceComponent < ViewComponent::Base
  def initialize(rows:, fiscal_year_label:)
    @rows              = rows
    @fiscal_year_label = fiscal_year_label
  end

  def formatted_amount(amount)
    Accounting::MoneyPresenter.new(amount).format
  end

  def total_debit
    @rows.sum { |r| r[:debit] }
  end

  def total_credit
    @rows.sum { |r| r[:credit] }
  end
end

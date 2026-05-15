class Accounting::DatePresenter
  def initialize(date)
    @date = date
  end

  def format
    return "" if @date.nil?
    @date.strftime("%d/%m/%Y")
  end

  def month_year
    @date.strftime("%m/%Y")
  end

  def vat_period
    quarter = ((@date.month - 1) / 3) + 1
    "T#{quarter} #{@date.year}"
  end
end

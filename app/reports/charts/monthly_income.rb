# R08 monthly view: income and expenses per month as bars, the period result as a line.
# `rows` = Accounting::AnnualAccounts::MonthlyRow list; no figure is recomputed here.
module Charts
  class MonthlyIncome
    INCOME  = %w[70/76A 75/76B 76].freeze
    CHARGES = %w[60/66A 65/66B 66].freeze
    RESULT  = "9904"

    def self.call(rows)
      by_code = rows.index_by(&:code)
      series  = ->(codes) { (0...12).map { |i| codes.sum(BigDecimal("0")) { |c| by_code[c]&.months&.at(i) || 0 } } }

      Base.base_option(
        legend: { data: [ "Income", "Expenses", "Result" ], textStyle: { color: Base::MUTED } },
        xAxis: { type: "category", data: (1..12).map { |n| "M#{n}" } },
        yAxis: { type: "value" },
        series: [
          { name: "Income",   type: "bar", itemStyle: { color: Base::OK },     data: series.(INCOME).map { |v| Base.money(v) } },
          { name: "Expenses", type: "bar", itemStyle: { color: Base::DANGER }, data: series.(CHARGES).map { |v| Base.money(v) } },
          { name: "Result",   type: "line", itemStyle: { color: Base::PRIMARY }, data: (by_code[RESULT]&.months || Array.new(12, 0)).map { |v| Base.money(v) } }
        ]
      )
    end
  end
end

# R15: waterfall from opening to closing cash through the operating, investing and financing flows
# (spec §17.2), built from the statement's own section totals.
module Charts
  class CashFlowWaterfall
    def self.call(statement)
      steps = [ [ "Opening", statement.opening_cash, :total ] ]
      %i[operating investing financing transfer unclassified].each do |section|
        amount = statement.direct.section_total(section)
        steps << [ section.to_s.humanize, amount, :flow ] unless amount.zero? && %i[transfer unclassified].include?(section)
      end
      steps << [ "Closing", statement.closing_cash, :total ]

      level = BigDecimal("0")
      base = []
      up = []
      down = []
      total = []
      steps.each do |_, amount, kind|
        if kind == :total
          base << 0; up << 0; down << 0; total << Base.money(amount)
          level = amount
        else
          low = [ level, level + amount ].min
          base << Base.money(low); up << Base.money([ amount, 0 ].max); down << Base.money([ -amount, 0 ].max); total << 0
          level += amount
        end
      end
      Base.base_option(
        tooltip: { trigger: "axis", axisPointer: { type: "shadow" } },
        xAxis: { type: "category", data: steps.map(&:first) },
        yAxis: { type: "value" },
        series: [
          { name: "base", type: "bar", stack: "w", itemStyle: { color: "transparent" }, data: base, tooltip: { show: false } },
          { name: "Cash", type: "bar", stack: "w", itemStyle: { color: Base::PRIMARY }, data: total },
          { name: "Inflow", type: "bar", stack: "w", itemStyle: { color: Base::OK }, data: up },
          { name: "Outflow", type: "bar", stack: "w", itemStyle: { color: Base::DANGER }, data: down }
        ]
      )
    end
  end
end

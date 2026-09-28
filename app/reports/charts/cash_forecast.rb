# R14: closing balance per week, one line per scenario, with the alert threshold (spec §17.2).
module Charts
  class CashForecast
    COLORS = { base: Base::PRIMARY, prudent: Base::DANGER, optimistic: Base::OK }.freeze

    def self.call(forecasts, threshold:)
      weeks = forecasts.values.first.weeks
      Base.base_option(
        legend: { data: forecasts.keys.map { |s| s.to_s.capitalize }, textStyle: { color: Base::MUTED } },
        xAxis: { type: "category", data: weeks.map { |w| w.from.strftime("%d/%m") } },
        yAxis: { type: "value", scale: true },
        series: forecasts.map { |scenario, result|
          { name: scenario.to_s.capitalize, type: "line", showSymbol: false, itemStyle: { color: COLORS.fetch(scenario) },
            data: result.weeks.map { |w| Base.money(w.closing) } }
        }.tap { |series| series.first[:markLine] = { silent: true, symbol: "none", lineStyle: { color: Base::WARNING, type: "dashed" },
                                                     data: [ { yAxis: Base.money(BigDecimal(threshold.to_s)), name: "Threshold" } ] } }
      )
    end
  end
end

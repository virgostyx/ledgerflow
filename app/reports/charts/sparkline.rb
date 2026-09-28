# 12-month trend under a dashboard card (R13). `points` = [[label, value_or_nil], ...].
module Charts
  class Sparkline
    def self.call(points, color: Base::PRIMARY)
      Base.base_option(
        grid: { left: 0, right: 0, top: 4, bottom: 0 },
        xAxis: { type: "category", show: false, data: points.map(&:first) },
        yAxis: { type: "value", show: false, scale: true },
        series: [ { type: "line", smooth: true, showSymbol: false, lineStyle: { color: color, width: 2 },
                    areaStyle: { color: color, opacity: 0.08 }, data: points.map { |_, v| Base.money(v) } } ]
      )
    end
  end
end

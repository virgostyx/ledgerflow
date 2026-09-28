# R04: one stacked bar per ageing bucket (totals) plus the ten biggest balances (spec §17.2).
module Charts
  class AgedBuckets
    BUCKET_COLORS = { not_due: Base::OK, days_1_30: "#84cc16", days_31_60: Base::WARNING, days_61_90: "#ea580c", over_90: Base::DANGER }.freeze

    def self.buckets(totals)
      Base.base_option(
        tooltip: { trigger: "item" },
        xAxis: { type: "category", data: Accounting::AgedBalanceQuery::BUCKETS.map { |b| b.to_s.humanize } },
        yAxis: { type: "value" },
        series: [ { type: "bar", data: Accounting::AgedBalanceQuery::BUCKETS.map { |b|
          { value: Base.money(totals.public_send(b)), itemStyle: { color: BUCKET_COLORS.fetch(b) } } } } ]
      )
    end

    def self.top_partners(rows, limit: 10)
      top = rows.sort_by { |r| -r.total }.first(limit).reverse
      Base.base_option(
        tooltip: { trigger: "axis", axisPointer: { type: "shadow" } },
        xAxis: { type: "value" },
        yAxis: { type: "category", data: top.map { |r| r.partner_name || "—" } },
        series: Accounting::AgedBalanceQuery::BUCKETS.map { |b|
          { name: b.to_s.humanize, type: "bar", stack: "total", itemStyle: { color: BUCKET_COLORS.fetch(b) },
            data: top.map { |r| Base.money(r.public_send(b)) } } }
      )
    end
  end
end

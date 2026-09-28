# Shared look for every chart (docs/dev/reports/spec.md §17.1): palette aligned with the app's
# Tailwind tokens and with the R13 severity colours. Builders return a plain ECharts option Hash
# from already-computed report figures; they never query the ledger. `currency` lets the Stimulus
# controller format tooltips and axes with the viewer's locale.
module Charts
  module Base
    PRIMARY = "#2563eb"
    OK      = "#059669"
    WARNING = "#d97706"
    DANGER  = "#dc2626"
    MUTED   = "#9ca3af"

    module_function

    def money(value) = value.nil? ? nil : value.to_f.round(2)

    def base_option(**extra)
      { textStyle: { color: MUTED }, animation: false, grid: { left: 8, right: 8, top: 24, bottom: 8, containLabel: true },
        tooltip: { trigger: "axis" }, currency: "EUR" }.merge(extra)
    end
  end
end

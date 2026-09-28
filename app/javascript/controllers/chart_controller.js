import { Controller } from "@hotwired/stimulus"

// Renders an ECharts option passed as JSON (docs/dev/reports/spec.md §17.1). The chart is only
// mounted once it scrolls into view; the table next to it stays usable without JavaScript.
export default class extends Controller {
  static values = { option: Object, height: { type: Number, default: 240 } }

  connect() {
    this.element.style.height = `${this.heightValue}px`
    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        this.observer.disconnect()
        this.mount()
      }
    })
    this.observer.observe(this.element)
  }

  // The server sends plain JSON; money formatting follows the viewer's locale (spec §17.1).
  withLocaleFormatting(option) {
    if (!option.currency) return option
    const fmt = new Intl.NumberFormat(document.documentElement.lang || undefined, { style: "currency", currency: option.currency })
    option.tooltip = { ...option.tooltip, valueFormatter: (v) => (v == null ? "—" : fmt.format(v)) }
    for (const axis of [option.xAxis, option.yAxis]) {
      if (axis && axis.type === "value" && axis.show !== false) axis.axisLabel = { ...axis.axisLabel, formatter: (v) => fmt.format(v) }
    }
    return option
  }

  disconnect() {
    this.observer?.disconnect()
    this.chart?.dispose()
    window.removeEventListener("resize", this.resize)
  }

  async mount() {
    const echarts = await import("echarts")
    this.chart = echarts.init(this.element)
    this.chart.setOption(this.withLocaleFormatting(this.optionValue))
    this.resize = () => this.chart.resize()
    window.addEventListener("resize", this.resize)
  }
}

# Mounts an ECharts option (built by a Charts::* builder from the same data as the table next
# to it — docs/dev/reports/spec.md §17) through the `chart` Stimulus controller.
class Reports::ChartComponent < ViewComponent::Base
  def initialize(option:, title:, height: 240)
    @option = option
    @title  = title
    @height = height
  end

  def call
    tag.div(role: "img", "aria-label": @title, data: { controller: "chart", chart_option_value: @option.to_json, chart_height_value: @height },
            class: "w-full")
  end
end

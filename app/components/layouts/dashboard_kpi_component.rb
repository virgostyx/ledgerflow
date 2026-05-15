class Layouts::DashboardKpiComponent < ViewComponent::Base
  def initialize(kpis:)
    @kpis = kpis
  end
end

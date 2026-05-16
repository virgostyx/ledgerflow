class Ui::FilterPanelComponent < ViewComponent::Base
  renders_one :fields

  def initialize(active_count: 0)
    @active_count = active_count.to_i
  end

  def open_by_default?
    @active_count > 0
  end
end

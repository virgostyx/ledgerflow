class Ui::BreadcrumbsComponent < ViewComponent::Base
  def initialize(items:)
    @items = items
  end

  def render?
    @items.present?
  end
end

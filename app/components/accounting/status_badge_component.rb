class Accounting::StatusBadgeComponent < ViewComponent::Base
  def initialize(status:)
    @presenter = Accounting::StatusPresenter.new(status)
  end

  def label
    @presenter.label
  end

  def variant
    @presenter.badge_variant
  end
end

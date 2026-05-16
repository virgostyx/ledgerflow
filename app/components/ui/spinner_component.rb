class Ui::SpinnerComponent < ViewComponent::Base
  SIZES = {
    sm: "h-4 w-4",
    md: "h-6 w-6",
    lg: "h-8 w-8"
  }.freeze

  def initialize(size: :sm)
    @size = size
  end

  def css_classes
    "animate-spin text-primary-600 #{SIZES[@size]}"
  end
end

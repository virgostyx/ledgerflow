class Ui::TooltipComponent < ViewComponent::Base
  POSITIONS = {
    top:    "bottom-full left-1/2 -translate-x-1/2 mb-2",
    bottom: "top-full left-1/2 -translate-x-1/2 mt-2",
    left:   "right-full top-1/2 -translate-y-1/2 mr-2",
    right:  "left-full top-1/2 -translate-y-1/2 ml-2"
  }.freeze

  def initialize(text:, position: :top)
    @text     = text
    @position = position
  end

  def tooltip_classes
    [
      "absolute z-50 px-3 py-2",
      "bg-gray-900 text-white text-xs rounded-lg shadow-lg",
      "whitespace-nowrap pointer-events-none",
      "opacity-0 invisible transition-all duration-200",
      "group-hover:opacity-100 group-hover:visible",
      POSITIONS.fetch(@position, POSITIONS[:top])
    ].join(" ")
  end
end

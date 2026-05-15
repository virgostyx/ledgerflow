class Ui::ButtonComponent < ViewComponent::Base
  VARIANTS = {
    primary:   "bg-indigo-600 hover:bg-indigo-700 text-white border-transparent",
    secondary: "bg-white hover:bg-gray-50 text-gray-700 border-gray-300",
    danger:    "bg-red-600 hover:bg-red-700 text-white border-transparent"
  }.freeze

  def initialize(label:, variant: :primary, type: "button", disabled: false, **html_options)
    @label        = label
    @variant      = variant
    @type         = type
    @disabled     = disabled
    @html_options = html_options
  end

  def call
    tag.button(
      @label,
      type: @type,
      disabled: @disabled || nil,
      class: css_classes,
      **@html_options
    )
  end

  private

  def css_classes
    base = "inline-flex items-center justify-center px-4 py-2 border rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500"
    disabled_classes = @disabled ? "opacity-50 cursor-not-allowed" : ""
    "#{base} #{VARIANTS[@variant]} #{disabled_classes}".strip
  end
end

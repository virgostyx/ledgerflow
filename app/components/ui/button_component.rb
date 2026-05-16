class Ui::ButtonComponent < ViewComponent::Base
  VARIANTS = {
    primary:   "bg-primary-600 hover:bg-primary-700 text-white border-transparent",
    secondary: "bg-white hover:bg-gray-50 text-gray-700 border-gray-300",
    danger:    "bg-red-600 hover:bg-red-700 text-white border-transparent",
    ghost:     "bg-transparent text-primary-600 border-primary-300 hover:bg-primary-50"
  }.freeze

  SIZES = {
    xs: "px-2 py-1 text-xs",
    sm: "px-3 py-1.5 text-sm",
    md: "px-4 py-2 text-sm",
    lg: "px-5 py-2.5 text-base",
    xl: "px-6 py-3 text-base"
  }.freeze

  def initialize(label:, variant: :primary, size: :md, type: "button", disabled: false, loading: false, icon: nil, **html_options)
    @label        = label
    @variant      = variant
    @size         = size
    @type         = type
    @loading      = loading
    @disabled     = disabled || loading
    @icon         = icon
    @html_options = html_options
  end

  def call
    tag.button(
      button_content,
      type: @type,
      disabled: @disabled || nil,
      class: css_classes,
      **@html_options
    )
  end

  private

  def button_content
    safe_join([ spinner_html, icon_html, @label ].compact)
  end

  def spinner_html
    return unless @loading

    tag.svg(class: "animate-spin -ml-1 mr-2 h-4 w-4", fill: "none", viewBox: "0 0 24 24") do
      safe_join([
        tag.circle(class: "opacity-25", cx: "12", cy: "12", r: "10", stroke: "currentColor", stroke_width: "4"),
        tag.path(class: "opacity-75", fill: "currentColor", d: "M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z")
      ])
    end
  end

  def icon_html
    return if @loading
    return unless @icon.present?

    tag.span(@icon.html_safe, class: "mr-2 inline-flex")
  end

  def css_classes
    base = "inline-flex items-center justify-center border rounded-lg font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-primary-500"
    size    = SIZES[@size] || SIZES[:md]
    variant = VARIANTS[@variant] || VARIANTS[:primary]
    disabled_cls = @disabled ? "opacity-50 cursor-not-allowed" : ""
    "#{base} #{size} #{variant} #{disabled_cls}".strip
  end
end

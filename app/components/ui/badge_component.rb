class Ui::BadgeComponent < ViewComponent::Base
  VARIANTS = {
    default: "bg-gray-100 text-gray-700",
    success: "bg-emerald-100 text-emerald-700",
    warning: "bg-amber-100 text-amber-700",
    danger:  "bg-red-100 text-red-700",
    primary: "bg-indigo-100 text-indigo-700"
  }.freeze

  def initialize(label:, variant: :default)
    raise ArgumentError, "Unknown variant: #{variant}" unless VARIANTS.key?(variant)
    @label   = label
    @variant = variant
  end

  def css_classes
    "#{VARIANTS[@variant]} inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
  end
end

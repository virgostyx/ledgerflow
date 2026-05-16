class Ui::AlertComponent < ViewComponent::Base
  VARIANTS = {
    info:    { bg: "bg-primary-50", text: "text-primary-700", border: "border-primary-200" },
    success: { bg: "bg-emerald-50", text: "text-emerald-700", border: "border-emerald-200" },
    warning: { bg: "bg-amber-50", text: "text-amber-700", border: "border-amber-200" },
    danger:  { bg: "bg-red-50", text: "text-red-700", border: "border-red-200" }
  }.freeze

  def initialize(message:, variant: :info, title: nil)
    @message = message
    @variant = variant
    @title   = title
  end

  def classes
    v = VARIANTS[@variant]
    "#{v[:bg]} #{v[:border]} #{v[:text]} border rounded-lg p-4"
  end

  def text_class
    VARIANTS[@variant][:text]
  end
end

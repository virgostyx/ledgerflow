class FlashMessageComponent < ViewComponent::Base
  def initialize(type:, message:, duration: 5000)
    @type     = type.to_sym
    @message  = message
    @duration = duration
    @config   = config_for(@type)
  end

  private

  attr_reader :type, :message, :duration, :config

  def config_for(type)
    case type
    when :notice, :success
      {
        bg:             "bg-emerald-50",
        border:         "border-emerald-200",
        text:           "text-emerald-800",
        icon_bg:        "bg-emerald-100",
        icon_color:     "text-emerald-600",
        icon_path:      "M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
        progress_color: "bg-emerald-400"
      }
    when :alert, :warning
      {
        bg:             "bg-amber-50",
        border:         "border-amber-200",
        text:           "text-amber-800",
        icon_bg:        "bg-amber-100",
        icon_color:     "text-amber-600",
        icon_path:      "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z",
        progress_color: "bg-amber-400"
      }
    when :error, :danger
      {
        bg:             "bg-red-50",
        border:         "border-red-200",
        text:           "text-red-800",
        icon_bg:        "bg-red-100",
        icon_color:     "text-red-600",
        icon_path:      "M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
        progress_color: "bg-red-400"
      }
    else # :info or unknown
      {
        bg:             "bg-primary-50",
        border:         "border-primary-200",
        text:           "text-primary-800",
        icon_bg:        "bg-primary-100",
        icon_color:     "text-primary-600",
        icon_path:      "M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z",
        progress_color: "bg-primary-400"
      }
    end
  end
end

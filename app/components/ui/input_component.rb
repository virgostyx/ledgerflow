class Ui::InputComponent < ViewComponent::Base
  def initialize(name:, label:, value: nil, type: "text", placeholder: nil,
                 required: false, disabled: false, error: nil, **html_options)
    @name         = name
    @label        = label
    @value        = value
    @type         = type
    @placeholder  = placeholder
    @required     = required
    @disabled     = disabled
    @error        = error
    @html_options = html_options
  end

  def input_classes
    base = "block w-full rounded-lg border px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
    @error ? "#{base} border-red-500" : "#{base} border-gray-300"
  end
end

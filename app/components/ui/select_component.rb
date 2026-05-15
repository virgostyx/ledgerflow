class Ui::SelectComponent < ViewComponent::Base
  def initialize(name:, label:, options:, selected: nil, prompt: nil, error: nil)
    @name     = name
    @label    = label
    @options  = options
    @selected = selected
    @prompt   = prompt
    @error    = error
  end
end

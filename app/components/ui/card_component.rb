class Ui::CardComponent < ViewComponent::Base
  renders_one :header
  renders_one :footer

  def initialize(title: nil, subtitle: nil, flat: false, shadow: true)
    @title    = title
    @subtitle = subtitle
    @flat     = flat || !shadow
  end

  def wrapper_classes
    base = "bg-white rounded-xl border border-gray-200 overflow-hidden"
    @flat ? base : "#{base} shadow-sm"
  end
end

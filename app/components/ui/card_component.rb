class Ui::CardComponent < ViewComponent::Base
  def initialize(title: nil, subtitle: nil, flat: false)
    @title    = title
    @subtitle = subtitle
    @flat     = flat
  end

  def wrapper_classes
    base = "bg-white rounded-xl border border-gray-200 p-6"
    @flat ? base : "#{base} shadow-sm"
  end
end

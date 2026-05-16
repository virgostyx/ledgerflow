class Ui::PageHeaderComponent < ViewComponent::Base
  renders_one :actions

  def initialize(title:, description: nil, back_path: nil, back_text: "Back")
    @title       = title
    @description = description
    @back_path   = back_path
    @back_text   = back_text
  end
end

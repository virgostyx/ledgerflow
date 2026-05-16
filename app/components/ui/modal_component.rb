class Ui::ModalComponent < ViewComponent::Base
  renders_one :footer

  ALIGNMENTS = { center: "items-center", top: "items-start pt-16" }.freeze

  def initialize(title:, align: :center)
    @title = title
    @align = align
  end

  def alignment_class
    ALIGNMENTS.fetch(@align, ALIGNMENTS[:center])
  end
end

class Accounting::JournalEntryRowComponent < ViewComponent::Base
  def initialize(entry:)
    @entry = entry
  end

  def formatted_date
    Accounting::DatePresenter.new(@entry.entry_date).format
  end
end

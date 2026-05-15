module Accounting::Statusable
  extend ActiveSupport::Concern

  included do
    enum :status, { draft: 0, posted: 1, reversed: 2 }

    include AASM

    aasm column: :status, enum: true do
      state :draft,    initial: true
      state :posted
      state :reversed

      event :post do
        transitions from: :draft, to: :posted
      end

      event :reverse do
        transitions from: :posted, to: :reversed
      end
    end
  end
end

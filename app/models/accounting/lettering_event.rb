# One line of the history of a line (F04): lettered or unlettered, under which code, by whom (nil: the system), whether
# automatically, and why. Kept after the lettering itself is deleted. Never changed.
class Accounting::LetteringEvent < ApplicationRecord
  self.table_name = "accounting_lettering_events"

  ACTIONS = %w[letter unletter].freeze

  acts_as_tenant :entity

  belongs_to :user, optional: true

  validates :line_id, :code, presence: true
  validates :action, inclusion: { in: ACTIONS }

  before_update { raise Accounting::ImmutableRecordError, "The history of a lettering is never changed" }
  before_destroy { raise Accounting::ImmutableRecordError, "The history of a lettering is never changed" }

  def self.record!(lines:, action:, code:, user: nil, auto: false, reason: nil)
    lines.each { |line| create!(line_id: line.id, action: action, code: code, user: user, auto: auto, reason: reason.presence) }
  end
end

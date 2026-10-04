# The 18 steps of the closing, in order (F10).
module Closing::Registry
  CODES = %w[preparation entries_complete bank partners vat fixed_assets accruals stock provisions taxes suspense revaluation consistency
             analytical_review closing_entries carry_forward lock_and_bundle approval].freeze

  def self.steps = CODES.map { |code| "Closing::Steps::#{code.camelize}".constantize }

  def self.fetch(code) = steps.find { |step| step.code == code.to_s }
end

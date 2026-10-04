# One step of the closing (F10, docs/dev/features/spec.md §12). A subclass says its place, kind and whether it blocks, and how to read its state now:
# `evaluate` returns a Closing::Outcome and never changes the books. Checks and actions are read live whenever asked; a manual step has no evaluation
# of its own, a person confirms it. What an action does is its `perform`.
class Closing::Step
  class_attribute :position, :code, :title, :kind, :blocking, instance_accessor: false

  attr_reader :run, :fiscal_year

  def initialize(run)
    @run = run
    @fiscal_year = run.fiscal_year
  end

  def evaluate = Closing::Outcome.new(:pending)

  private

  def ok(details = {})      = Closing::Outcome.new(:ok, details)
  def warning(details = {}) = Closing::Outcome.new(:warning, details)
  def blocked(details = {}) = Closing::Outcome.new(:blocked, details)
  def pending(details = {}) = Closing::Outcome.new(:pending, details)

  def year_end = fiscal_year.end_date
  def money(value) = value.to_d.to_s("F")
end

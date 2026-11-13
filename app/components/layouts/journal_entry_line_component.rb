# One line of the journal entry form. The same markup is rendered for the saved lines and for the new-line <template>
# (form builder with child_index "NEW_INDEX"), so the two cannot drift apart.
class Layouts::JournalEntryLineComponent < ViewComponent::Base
  FIELD = "block w-full rounded-md border border-gray-300 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-primary-500".freeze
  FIELD_SMALL = FIELD.sub("text-sm", "text-xs").freeze

  def initialize(form:, axes:, partners:, currency_options:)
    @form             = form
    @axes             = axes
    @partners         = partners
    @currency_options = currency_options
  end

  private

  attr_reader :form, :axes, :partners, :currency_options

  def line = form.object

  # Currency and analytics are rare: folded away unless the line already uses them.
  def extras_open?
    (line.currency.present? && line.currency != "EUR") ||
      line.amount_currency.present? ||
      (axes.any? && line.analytical_annotations.any? { |a| a.analytical_account_id.present? })
  end

  def annotation_for(axis)
    line.analytical_annotations.find { |a| a.analytical_axis_id == axis.id } ||
      Accounting::AnalyticalAnnotation.new(analytical_axis: axis)
  end
end

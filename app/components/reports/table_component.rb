# Generic table for any Reports::Result (docs/dev/reports/spec.md §2.1/§2.5):
# sticky header, tabular-nums right-aligned numeric columns, a totals footer
# when the result carries one, client-side sort (report_table_controller.js —
# tri côté client per §2.5, unlike Ui::ColumnHeaderComponent's server-side
# sort/filter for CRUD list pages).
#
# columns: an array of { key:, label:, align: (optional), format: (optional proc) }.
# key is a Symbol (row.public_send(key)) or a callable (key.call(row)).
class Reports::TableComponent < ViewComponent::Base
  def initialize(result:, columns:, id: nil)
    @result  = result
    @columns = columns
    @id      = id
  end

  private

  attr_reader :result, :columns, :id

  def extract(row, column)
    key = column[:key]
    key.respond_to?(:call) ? key.call(row) : row.public_send(key)
  end

  def numeric?(value)
    value.is_a?(BigDecimal) || value.is_a?(Float) || value.is_a?(Integer)
  end

  # A column with no explicit :align follows the first row's value type — every
  # row of a column has the same shape, so this is stable across the table.
  def align_class(column)
    align = column[:align] || (numeric?(extract(result.rows.first, column)) ? :right : :left) if result.rows.first
    align ||= column[:align] || :left
    align == :right ? "text-right" : "text-left"
  end

  def formatted(value, column)
    return column[:format].call(value) if column[:format]
    return value.to_s unless numeric?(value)

    Accounting::MoneyPresenter.new(value, currency: result.currency).format
  end

  def total_for(column)
    return unless result.totals&.key?(column[:key])

    result.totals[column[:key]]
  end
end

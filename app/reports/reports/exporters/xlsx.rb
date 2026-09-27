# Renders a Reports::Result as XLSX (docs/dev/reports/spec.md §14): typed
# numeric cells, a frozen header row, real =SUM() formulas (with a cached
# value, so the file opens with correct totals before Excel recalculates),
# and a "Paramètres" sheet listing every filter and the generation date, so
# an export is reproducible.
class Reports::Exporters::Xlsx
  def self.call(result, columns:, title: "Report")
    new(result, columns: columns, title: title).call
  end

  def initialize(result, columns:, title:)
    @result  = result
    @columns = columns
    @title   = title.to_s[0, 31] # Excel's sheet-name length limit
  end

  def call
    package = Axlsx::Package.new
    data_sheet(package)
    settings_sheet(package)
    package.to_stream.read
  end

  private

  attr_reader :result, :columns, :title

  def data_sheet(package)
    package.workbook.add_worksheet(name: title) do |sheet|
      sheet.add_row(columns.map(&:first), style: header_style(sheet))
      values_by_column = columns.map { [] }

      result.rows.each do |row|
        values = columns.map { |_, extractor| extract(row, extractor) }
        values.each_with_index { |v, i| values_by_column[i] << v }
        sheet.add_row(values, types: values.map { |v| cell_type(v) })
      end

      add_totals_row(sheet, values_by_column) if result.rows.any?
      sheet.sheet_view.pane { |pane| pane.state = :frozen; pane.y_split = 1; pane.top_left_cell = "A2" }
      sheet.column_widths(*columns.map { |label, _| [ label.length, 12 ].max })
      sheet.page_setup.orientation = :landscape
      sheet.page_setup.fit_to_width = 1
    end
  end

  def add_totals_row(sheet, values_by_column)
    last_row = result.rows.size + 1
    numeric_column = columns.each_index.map { |i| values_by_column[i].all? { |v| v.is_a?(Numeric) } }

    cells = columns.each_index.map do |i|
      next "=SUM(#{Axlsx.col_ref(i)}2:#{Axlsx.col_ref(i)}#{last_row})" if numeric_column[i]

      i.zero? ? "Total" : nil
    end
    cached = columns.each_index.map { |i| numeric_column[i] ? values_by_column[i].sum : nil }

    # escape_formulas: false — these formulas are generated here, not user input, so no CSV-injection risk.
    sheet.add_row(cells, types: Array.new(columns.size, :string), formula_values: cached,
                  escape_formulas: false, style: header_style(sheet))
  end

  def settings_sheet(package)
    package.workbook.add_worksheet(name: "Paramètres") do |sheet|
      sheet.add_row([ "Généré le", result.generated_at.to_s ])
      (result.filters&.attributes || {}).each { |key, value| sheet.add_row([ key, value.to_s ]) }
    end
  end

  def header_style(sheet)
    sheet.styles.add_style(b: true)
  end

  def extract(row, extractor)
    extractor.respond_to?(:call) ? extractor.call(row) : row.public_send(extractor)
  end

  def cell_type(value)
    value.is_a?(BigDecimal) || value.is_a?(Float) || value.is_a?(Integer) ? :float : :string
  end
end

# Renders a Reports::Result as PDF (docs/dev/reports/spec.md §14): A4
# landscape, title and page numbers repeated per page, via Prawn/prawn-table —
# the gems this app already uses for Accounting::InvoicePdf. Not Ferrum/HTML
# rendering: no report view templates exist yet to reuse the print CSS from,
# and this generic tabular exporter needs none — see docs/dev/reports/QUESTIONS.md.
class Reports::Exporters::Pdf
  def self.call(result, columns:, title: "Report")
    new(result, columns: columns, title: title).call
  end

  def initialize(result, columns:, title:)
    @result  = result
    @columns = columns
    @title   = title
  end

  def call
    pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 30, info: { Title: title })
    pdf.font "Helvetica"
    pdf.text title, size: 14, style: :bold
    pdf.move_down 10
    pdf.table(table_rows, header: true, width: pdf.bounds.width) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = "EEEEEE"
      t.cells.padding = 4
    end
    pdf.number_pages "<page> / <total>", at: [ pdf.bounds.right - 100, 0 ], align: :right
    pdf.render
  end

  private

  attr_reader :result, :columns, :title

  def table_rows
    [ columns.map(&:first) ] + result.rows.map { |row| columns.map { |_, extractor| t(extract(row, extractor)) } }
  end

  def extract(row, extractor)
    extractor.respond_to?(:call) ? extractor.call(row) : row.public_send(extractor)
  end

  def t(value)
    case value
    when BigDecimal, Float then format("%.2f", value)
    else value.to_s
    end
  end
end

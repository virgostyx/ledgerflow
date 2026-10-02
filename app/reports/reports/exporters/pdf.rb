# Renders a Reports::Result as PDF (docs/dev/reports/spec.md §14): A4
# landscape, title and page numbers repeated per page, via Prawn/prawn-table —
# the gems this app already uses for Accounting::InvoicePdf. Not Ferrum/HTML
# rendering: no report view templates exist yet to reuse the print CSS from,
# and this generic tabular exporter needs none — see docs/dev/reports/QUESTIONS.md.
class Reports::Exporters::Pdf
  # `watermark`: a name stamped diagonally on every page (the external auditor's, F01).
  def self.call(result, columns:, title: "Report", watermark: nil)
    new(result, columns: columns, title: title, watermark: watermark).call
  end

  def initialize(result, columns:, title:, watermark: nil)
    @result  = result
    @columns = columns
    @title   = title
    @watermark = watermark
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
    stamp_watermark(pdf) if watermark.present?
    pdf.render
  end

  private

  attr_reader :result, :columns, :title, :watermark

  # Light, large and diagonal, so the table underneath stays readable. Built-in Helvetica only draws Windows-1252.
  def stamp_watermark(pdf)
    text = watermark.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
    center = [ pdf.bounds.width / 2, pdf.bounds.height / 2 ]
    size = [ 36, 480.0 / (text.length * 0.65) ].min # one line, whatever the length of the name
    pdf.page_count.times do |i|
      pdf.go_to_page(i + 1)
      pdf.transparent(0.15) do
        pdf.rotate(30, origin: center) do
          pdf.text_box text, at: [ center.first - 250, center.last + size / 2 ], width: 500, align: :center, size: size, style: :bold, single_line: true
        end
      end
    end
  end

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

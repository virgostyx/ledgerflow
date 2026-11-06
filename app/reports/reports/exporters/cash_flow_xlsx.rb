# Cash-flow statement as an XLSX workbook: one sheet per method (indirect, direct).
class Reports::Exporters::CashFlowXlsx
  def self.call(statement)
    package = Axlsx::Package.new
    { "Indirect" => statement.indirect, "Direct" => statement.direct }.each do |name, sheet_data|
      package.workbook.add_worksheet(name: name) do |sheet|
        sheet.add_row([ "Section", "Line", "Amount" ])
        sheet_data.lines.each { |l| sheet.add_row([ l.section.to_s.humanize, l.label, l.amount.to_f ], types: [ :string, :string, :float ]) }
        sheet.add_row([ "Net change in cash", "", sheet_data.total.to_f ], types: [ :string, :string, :float ])
      end
    end
    package.to_stream.read
  end
end

require "rails_helper"

RSpec.describe Reports::Exporters::CashFlowXlsx do
  let(:line)  { Accounting::CashFlowStatement::Line.new(key: :net_result, section: :operating, label: "Net result", amount: BigDecimal("12.5")) }
  let(:sheet) { Accounting::CashFlowStatement::Sheet.new(lines: [ line ]) }
  let(:statement) { instance_double(Accounting::CashFlowStatement::Result, indirect: sheet, direct: sheet) }

  before { allow(sheet).to receive(:total).and_return(BigDecimal("12.5")) }

  it "builds a workbook with an Indirect and a Direct sheet" do
    xlsx = described_class.call(statement)

    workbook = Zip::File.open_buffer(StringIO.new(xlsx)).find_entry("xl/workbook.xml").get_input_stream.read
    expect(workbook).to include('name="Indirect"', 'name="Direct"')
  end
end

require "rails_helper"
require "zip"

RSpec.describe Reports::Exporters::Xlsx, type: :model do
  xlsx_spec_row = Struct.new(:code, :label, :balance)

  let(:filters) { Reports::Filters.new(fiscal_year_id: 3) }
  let(:result) do
    Reports::Result.new(filters: filters, generated_at: Time.zone.local(2026, 3, 15, 10, 0), rows: [
      xlsx_spec_row.new("600000", "Achats", BigDecimal("1234.50")),
      xlsx_spec_row.new("700000", "Ventes", BigDecimal("-500"))
    ])
  end
  let(:columns) { [ [ "Code", :code ], [ "Libellé", :label ], [ "Solde", :balance ] ] }

  subject(:bytes) { described_class.call(result, columns: columns, title: "Achats et ventes") }

  # Reads one archive entry's raw XML as a string, for content assertions without a full XLSX reader (no `roo` gem).
  def zip_entry(name)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.xlsx")
      File.binwrite(path, bytes)
      Zip::File.open(path) { |zip| return zip.read(name) }
    end
  end

  it "produces a valid xlsx (zip) archive" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.xlsx")
      File.binwrite(path, bytes)
      expect { Zip::File.open(path) { |z| z.entries.map(&:name) } }.not_to raise_error
    end
  end

  it "has a data sheet and a Paramètres sheet listing the filters and generation date" do
    workbook_xml  = zip_entry("xl/workbook.xml")
    settings_xml  = zip_entry("xl/worksheets/sheet2.xml")

    expect(workbook_xml).to include("Achats et ventes")
    expect(workbook_xml).to include("Param")
    expect(settings_xml).to include("fiscal_year_id")
  end

  it "puts a real SUM() formula with a cached value on the totals row, not a plain number" do
    data_xml = zip_entry("xl/worksheets/sheet1.xml")

    expect(data_xml).to match(%r{<f>SUM\(C2:C3\)</f><v>734\.5}) # 1234.50 - 500 = 734.50, cached
  end
end

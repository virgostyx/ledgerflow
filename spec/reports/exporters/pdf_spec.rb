require "rails_helper"
require "pdf/reader"

RSpec.describe Reports::Exporters::Pdf, type: :model do
  pdf_spec_row = Struct.new(:code, :label, :balance)

  let(:result) do
    Reports::Result.new(rows: [
      pdf_spec_row.new("600000", "Achats", BigDecimal("1234.50")),
      pdf_spec_row.new("700000", "Ventes", BigDecimal("-500"))
    ])
  end
  let(:columns) { [ [ "Code", :code ], [ "Libellé", :label ], [ "Solde", :balance ] ] }

  subject(:bytes) { described_class.call(result, columns: columns, title: "Achats et ventes") }

  def text
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.pdf")
      File.binwrite(path, bytes)
      PDF::Reader.new(path).pages.map(&:text).join("\n")
    end
  end

  it "produces a readable PDF with the title, header row and data" do
    body = text
    expect(body).to include("Achats et ventes")
    expect(body).to include("Code")
    expect(body).to include("600000")
    expect(body).to include("Achats")
  end

  it "is landscape A4" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "r.pdf")
      File.binwrite(path, bytes)
      page = PDF::Reader.new(path).pages.first
      expect(page.attributes[:MediaBox][2]).to be > page.attributes[:MediaBox][3] # width > height
    end
  end
end

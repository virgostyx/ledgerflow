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

  describe "watermark (F01: the name of an external auditor on every page)" do
    let(:many_rows) { Reports::Result.new(rows: Array.new(120) { |i| pdf_spec_row.new(format("%06d", i), "Account #{i}", BigDecimal(i)) }) }

    it "stamps the name on every page" do
      bytes = described_class.call(many_rows, columns: columns, title: "Long report", watermark: "Alice Auditor")

      expect(pdf_page_strings(bytes).size).to be > 1
      expect(watermarked_on_every_page?(bytes, "Alice Auditor")).to be true
    end

    it "leaves every page clean without a watermark" do
      bytes = described_class.call(many_rows, columns: columns, title: "Long report")

      expect(watermarked_on_no_page?(bytes, "Alice Auditor")).to be true
    end

    it "keeps the table intact under the watermark" do
      bytes = described_class.call(result, columns: columns, title: "Achats", watermark: "Alice Auditor")

      expect(pdf_page_strings(bytes).flatten).to include("600000", "Achats", "1234.50")
    end

    it "does not fail on a name the built-in font cannot draw, and draws what it can" do
      bytes = described_class.call(result, columns: columns, title: "Achats", watermark: "Ångström Łukasz 李")

      expect(watermarked_on_every_page?(bytes, "Ångström Łukasz 李")).to be true
    end

    it "keeps a very long name on one line" do
      name = "Maximilian Alexander Konstantinopolous-Papadimitriou Junior"
      bytes = described_class.call(result, columns: columns, title: "Achats", watermark: name)

      expect(watermarked_on_every_page?(bytes, name)).to be true
    end
  end
end

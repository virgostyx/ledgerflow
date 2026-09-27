require "rails_helper"

RSpec.describe Reports::TableComponent, type: :component do
  table_row = Struct.new(:code, :label, :balance)

  let(:columns) { [ { key: :code, label: "Code" }, { key: :label, label: "Libellé" }, { key: :balance, label: "Solde" } ] }
  let(:result) do
    Reports::Result.new(
      rows: [ table_row.new("600000", "Achats", BigDecimal("1234.5")), table_row.new("700000", "Ventes", BigDecimal("-500")) ],
      totals: { balance: BigDecimal("734.5") }
    )
  end

  subject!(:rendered) { render_inline(described_class.new(result: result, columns: columns)) }

  it "renders the header labels and every row's cells" do
    expect(page).to have_css("th", text: "Code")
    expect(page).to have_css("th", text: "Libellé")
    expect(page).to have_css("td", text: "600000")
    expect(page).to have_css("td", text: "Achats")
  end

  it "formats a numeric column with the report's currency and right-aligns it" do
    expect(page).to have_css("td.text-right", text: "1 234,50 €")
  end

  it "left-aligns a non-numeric column" do
    expect(page.find("td", text: "Achats")[:class]).to include("text-left")
  end

  it "renders a totals row when the result has totals" do
    expect(page).to have_css("tfoot td", text: "734,50 €")
  end

  it "gives the header a sticky position and the table a client-side sort controller" do
    expect(page).to have_css("thead.sticky")
    expect(page).to have_css("table[data-controller='report-table']")
  end

  context "without totals" do
    let(:result) { Reports::Result.new(rows: []) }

    it "renders no tfoot" do
      expect(page).to have_no_css("tfoot")
    end
  end
end

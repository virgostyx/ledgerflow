require "rails_helper"
require "zip"

RSpec.describe Knowledge::Extract do
  def docx(body_xml)
    io = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("word/document.xml")
      zip.write(%(<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>#{body_xml}</w:body></w:document>))
    end
    io.string
  end

  it "reads Markdown and plain text as they are" do
    expect(described_class.call("# Title\n\nText")).to eq("# Title\n\nText")
  end

  it "reads HTML, keeping the titles and the rows of a table, and dropping scripts" do
    html = "<html><body><script>alert(1)</script><h2>Leases</h2><p>Pay in <b>advance</b>.</p><table><tr><td>A</td><td>B</td></tr></table></body></html>"

    expect(described_class.call(html)).to eq("## Leases\n\nPay in advance.\n\nA | B")
  end

  it "reads a DOCX, keeping the headings" do
    xml = %(<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Insurance</w:t></w:r></w:p><w:p><w:r><w:t>Spread </w:t></w:r><w:r><w:t>it.</w:t></w:r></w:p>)

    expect(described_class.call(docx(xml))).to eq("# Insurance\n\nSpread it.")
  end

  it "refuses a DOCX whose XML declares entities" do
    bomb = %(<!DOCTYPE x [<!ENTITY a "aaaa">]><w:p><w:r><w:t>&a;</w:t></w:r></w:p>)

    expect { described_class.call(docx(bomb)) }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(:unsafe_xml) }
  end

  it "refuses what is empty, binary or an archive that is not a document" do
    expect { described_class.call("   ") }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(:empty) }
    expect { described_class.call("abc\u0000def") }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(:unsupported_type) }
    other = Zip::OutputStream.write_buffer { |zip| zip.put_next_entry("a.txt"); zip.write("x") }.string
    expect { described_class.call(other) }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(:unsupported_type) }
  end

  it "refuses a PDF it cannot read" do
    expect { described_class.call("%PDF-1.4 not really") }.to raise_error(described_class::Refused) { |e| expect(e.reason).to eq(:unreadable) }
  end
end

require "rails_helper"

# One PDF holding several invoices becomes one child document per range of pages, each linked to the parent.
RSpec.describe Accounting::SplitDocument do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:parent) do
    Accounting::UploadDocument.call(io: StringIO.new(sample_multipage_pdf("Invoice A 100,00", "Invoice B 200,00", "Invoice C 300,00")),
                                    filename: "scan-3-invoices.pdf", user: user, origin: :scan, kind: :purchase_invoice)[:document]
  end

  def pages_text(document) = PDF::Reader.new(StringIO.new(document.file.download)).pages.map { |page| page.text.squish }

  def split(ranges) = described_class.call(document: parent, ranges: ranges, user: user)

  describe "a PDF of three invoices" do
    it "gives three documents, one per page, each linked to the parent" do
      result = split("1,2,3")

      children = result[:children]
      expect(result).to be_success
      expect(children.size).to eq(3)
      expect(children.map(&:parent)).to all(eq(parent))
      expect(parent.reload.children).to match_array(children)
      expect(children.map { |child| pages_text(child) }).to eq([ [ "Invoice A 100,00" ], [ "Invoice B 200,00" ], [ "Invoice C 300,00" ] ])
    end

    it "takes ranges of several pages" do
      children = split("1-2, 3")[:children]

      expect(children.map { |child| pages_text(child).size }).to eq([ 2, 1 ])
      expect(pages_text(children.first)).to eq([ "Invoice A 100,00", "Invoice B 200,00" ])
    end

    it "lets some pages out (a cover sheet, a blank page)" do
      children = split("2")[:children]

      expect(children.size).to eq(1)
      expect(pages_text(children.first)).to eq([ "Invoice B 200,00" ])
    end
  end

  describe "the children" do
    let(:children) { split("1,2,3")[:children] }

    it "are ordinary documents: in the inbox, with their own checksum, kind and origin of the parent" do
      expect(children).to all(be_inbox)
      expect(children.map(&:sha256).uniq.size).to eq(3)
      expect(children.map(&:kind).uniq).to eq([ "purchase_invoice" ])
      expect(children.map(&:origin).uniq).to eq([ "scan" ])
    end

    it "are named after the parent and their pages" do
      expect(children.map(&:name)).to eq([ "scan-3-invoices (page 1).pdf", "scan-3-invoices (page 2).pdf", "scan-3-invoices (page 3).pdf" ])
    end

    it "are read like any upload" do
      parent
      expect { split("1,2,3") }.to have_enqueued_job(Accounting::ExtractDocumentJob).exactly(3).times
    end

    it "are audited as uploads, and the split is audited with its ranges" do
      children

      expect(Accounting::AuditLog.where(action: "document_upload").count).to eq(4) # the parent and the three children
      row = Accounting::AuditLog.where(action: "document_split", auditable_id: parent.id).sole
      expect(row.payload).to include("ranges" => "1,2,3", "children" => children.map(&:id))
    end
  end

  describe "the parent" do
    it "is left exactly as it was: same file, same checksum, still where it was" do
      before = [ parent.sha256, parent.file.download, parent.status, parent.kind ]

      split("1,2,3")

      parent.reload
      expect([ parent.sha256, parent.file.download, parent.status, parent.kind ]).to eq(before)
    end

    it "can be split even when it justifies a validated entry" do
      Accounting::LinkDocument.call(document: parent, target: create(:journal_entry, :posted), user: user)

      expect(split("1,2,3")).to be_success
    end
  end

  describe "ranges that are refused" do
    {
      "nothing"                      => "",
      "words"                        => "first page",
      "page zero"                    => "0",
      "a page the document does not have" => "4",
      "a range that goes backwards"  => "3-1",
      "ranges that overlap"          => "1-2,2-3",
      "the same page twice"          => "1,1",
      "the whole document (nothing to split)" => "1-3",
      "negative numbers"             => "-1",
      "an open range"                => "1-"
    }.each do |label, ranges|
      it "refuses #{label} (#{ranges.inspect}) and creates nothing" do
        result = split(ranges)

        expect(result).to be_failure
        expect(result.message).to be_present
        expect(Accounting::Document.where.not(parent_id: nil)).to be_empty
      end
    end

    it "refuses more ranges than a person could mean" do
      big = Accounting::UploadDocument.call(io: StringIO.new(sample_multipage_pdf(*Array.new(60) { |i| "Page #{i}" })), filename: "big.pdf", user: user)[:document]

      result = described_class.call(document: big, ranges: (1..55).to_a.join(","), user: user)

      expect(result).to be_failure
    end
  end

  describe "what cannot be split" do
    it "an image, a spreadsheet, an XML" do
      [ [ sample_png, "a.png" ], [ sample_xlsx, "a.xlsx" ], [ sample_ubl, "a.xml" ] ].each do |content, name|
        document = Accounting::UploadDocument.call(io: StringIO.new(content), filename: name, user: user)[:document]

        expect(described_class.call(document: document, ranges: "1", user: user)).to be_failure
      end
    end

    it "a PDF that asks for a password" do
      locked = Accounting::UploadDocument.call(io: StringIO.new(sample_encrypted_pdf), filename: "l.pdf", user: user)[:document]

      expect(described_class.call(document: locked, ranges: "1", user: user)).to be_failure
    end

    it "a PDF of one page" do
      single = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("only page")), filename: "one.pdf", user: user)[:document]

      expect(described_class.call(document: single, ranges: "1", user: user)).to be_failure
    end

    it "an archived document" do
      parent.update!(status: :archived)

      expect(split("1,2")).to be_failure
    end
  end

  describe "splitting twice" do
    it "reports the children that already exist instead of duplicating them" do
      first = split("1,2,3")[:children]

      again = split("1,2,3")

      expect(again).to be_failure
      expect(again[:refused].size).to eq(3)
      expect(Accounting::Document.where(parent: parent).count).to eq(first.size)
    end

    it "creates the new ones and reports the others" do
      split("1,2")

      again = split("2,3")

      expect(again).to be_success
      expect(again[:children].size).to eq(1)
      expect(again[:refused].size).to eq(1)
    end
  end

  it "never reaches for a file outside its own working directory" do
    evil = Accounting::UploadDocument.call(io: StringIO.new(sample_multipage_pdf("a", "b")), filename: "../../etc/passwd.pdf", user: user)[:document]

    result = described_class.call(document: evil, ranges: "1,2", user: user)

    expect(result).to be_success
    expect(result[:children].map(&:name)).to all(satisfy { |name| !name.include?("/") })
  end

  it "keeps the children of the entity of the parent" do
    result = split("1,2,3")

    expect(result[:children].map(&:entity_id).uniq).to eq([ entity.id ])
  end
end

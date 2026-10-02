require "rails_helper"

# What an external auditor is shown of a document: the file with their name across it, never the file as it is.
RSpec.describe Accounting::WatermarkFile do
  before { skip "ghostscript and ImageMagick are not installed here" unless %w[gs convert identify pdftoppm].all? { |tool| system("which", tool, out: File::NULL, err: File::NULL) } }

  let(:pdf) { sample_multipage_pdf("Invoice A 100,00", "Invoice B 200,00") }

  def reader(bytes) = PDF::Reader.new(StringIO.new(bytes))
  def text_of(bytes) = reader(bytes).pages.map { |page| page.text.squish }
  def raster(bytes) = Dir.mktmpdir { |dir| File.binwrite("#{dir}/in.pdf", bytes); system("pdftoppm", "-png", "-r", "60", "-f", "1", "-l", "1", "#{dir}/in.pdf", "#{dir}/p", exception: true); File.binread(Dir["#{dir}/p*.png"].first) }
  def dimensions(bytes, type) = Dir.mktmpdir { |dir| File.binwrite("#{dir}/i", bytes); `identify -format "%wx%h" #{type}:#{dir}/i`.strip }

  describe "a PDF" do
    let(:stamped) { described_class.call(pdf, "application/pdf", "Alice Auditor") }

    it "is still a PDF with the same pages and the same text (nothing is hidden)" do
      expect(reader(stamped).page_count).to eq(2)
      expect(text_of(stamped)).to eq(text_of(pdf))
    end

    it "carries the mark on the page, which differs from the original" do
      expect(raster(stamped)).not_to eq(raster(pdf))
    end

    it "says who it was shown to in the file's own properties" do
      expect(reader(stamped).info[:Subject].to_s).to include("Alice Auditor")
    end

    it "does not change the original bytes" do
      original = pdf.dup

      stamped

      expect(pdf).to eq(original)
    end

    it "marks every page, whatever its size" do
      mixed = Prawn::Document.new(page_size: "A4") { |p| p.text "A4 page"; p.start_new_page(size: "A3", layout: :landscape); p.text "A3 landscape page" }.render

      result = described_class.call(mixed, "application/pdf", "Alice Auditor")

      expect(reader(result).page_count).to eq(2)
      expect(text_of(result)).to eq(text_of(mixed))
    end
  end

  describe "a name that is not to be trusted" do
    [ "Alice) pop (Auditor", "Alice\\Auditor", "@/etc/passwd", "%[fx:1]%f", "Alice\nAuditor\r", "<< /EndPage {} >> setpagedevice", "Zoë Müller", "李 王", "a" * 500 ].each do |name|
      it "makes a valid, marked PDF with #{name[0, 30].inspect}" do
        result = described_class.call(pdf, "application/pdf", name)

        expect(reader(result).page_count).to eq(2)
        expect(text_of(result)).to eq(text_of(pdf))
        expect(raster(result)).not_to eq(raster(pdf))
        expect(reader(result).info[:Subject].to_s.length).to be < 200
      end
    end

    it "keeps only what is safe to write in a PostScript string and on an image" do
      expect(described_class.send(:safe_label, "Alice) pop (Auditor\n@x%y")).to eq("Alice pop Auditor x y")
      expect(described_class.send(:safe_label, "Zoë Müller")).to eq("Zoe Muller")
      expect(described_class.send(:safe_label, "a" * 500).length).to eq(Accounting::WatermarkFile::MAX_LABEL)
      expect(described_class.send(:safe_label, "   ")).to eq("Viewer")
    end
  end

  describe "an image" do
    {
      "a PNG" => [ -> { sample_png }, "image/png", "png" ],
      "a JPEG" => [ -> { sample_jpeg }, "image/jpeg", "jpeg" ]
    }.each do |label, (build, type, coder)|
      it "marks #{label}, keeping its type and size" do
        original = instance_exec(&build)

        result = described_class.call(original, type, "Alice Auditor")

        expect(result).not_to eq(original)
        expect(dimensions(result, coder)).to eq(dimensions(original, coder))
      end
    end

    it "marks a picture of a real page (a scan)" do
      png = render_pdf_to_png(pdf)

      result = described_class.call(png, "image/png", "Alice Auditor")

      expect(result).not_to eq(png)
      expect(result.b.start_with?("\x89PNG".b)).to be true
    end
  end

  describe "what it cannot mark" do
    it "refuses a type it has no way to mark, instead of passing it through" do
      expect { described_class.call(sample_csv, "text/csv", "Alice") }.to raise_error(Accounting::WatermarkFile::Unsupported)
      expect { described_class.call(sample_xlsx, Accounting::UploadDocument::XLSX, "Alice") }.to raise_error(Accounting::WatermarkFile::Unsupported)
    end

    it "fails rather than hands back an unmarked file when the tool breaks" do
      allow(Accounting::ExternalCommand).to receive(:run).and_raise(Accounting::ExternalCommand::Failed, "gs is not installed")

      expect { described_class.call(pdf, "application/pdf", "Alice") }.to raise_error(Accounting::WatermarkFile::Unavailable)
    end

    it "fails on a file that is not what it says" do
      expect { described_class.call("not a pdf", "application/pdf", "Alice") }.to raise_error(Accounting::WatermarkFile::Unavailable)
      expect { described_class.call("not a png", "image/png", "Alice") }.to raise_error(Accounting::WatermarkFile::Unavailable)
    end

    it "says which types it can mark" do
      expect(described_class.markable?("application/pdf")).to be true
      expect(described_class.markable?("image/png")).to be true
      expect(described_class.markable?("image/jpeg")).to be true
      expect(described_class.markable?("application/xml")).to be false
      expect(described_class.markable?("image/tiff")).to be false
    end
  end
end

require "rails_helper"

# The one way files come in (manual upload, e-mail): each file, and each file inside an archive, is an upload.
RSpec.describe Accounting::UploadFiles do
  include_context "with entity"

  let(:user) { create(:user) }

  def files(*pairs) = pairs.map { |content, name| [ StringIO.new(content), name ] }
  def zip(entries) = Accounting::Zipper.build(entries)
  def call(*pairs, **options) = described_class.call(files: files(*pairs), user: user, **options)

  describe "plain files" do
    it "uploads each one and reports the others" do
      result = call([ sample_pdf("one"), "one.pdf" ], [ sample_png, "two.png" ], [ sample_exe, "evil.pdf" ])

      expect(result.created.map(&:name)).to eq([ "one.pdf", "two.png" ])
      expect(result.refused).to contain_exactly(a_string_starting_with("evil.pdf: "))
    end

    it "carries the origin and the kind to every document" do
      result = call([ sample_pdf("mail"), "m.pdf" ], origin: :email, kind: :purchase_invoice)

      expect(result.created.first).to have_attributes(origin: "email", kind: "purchase_invoice")
    end

    it "says there was nothing when there was nothing" do
      expect(call.created).to be_empty
      expect(call.refused).to be_empty
    end
  end

  describe "an archive" do
    let(:archive) { zip([ [ "inv-1.pdf", sample_pdf("one") ], [ "scan.png", sample_png ], [ "notes/inv-2.pdf", sample_pdf("two") ] ]) }

    it "is unpacked: each file inside becomes a document" do
      result = call([ archive, "invoices.zip" ])

      expect(result.created.map(&:name)).to contain_exactly("inv-1.pdf", "scan.png", "inv-2.pdf")
      expect(result.refused).to be_empty
    end

    it "is not kept as a document itself" do
      call([ archive, "invoices.zip" ])

      expect(Accounting::Document.pluck(:name)).not_to include("invoices.zip")
    end

    it "reports what inside it was refused, naming the archive" do
      result = call([ zip([ [ "ok.pdf", sample_pdf("ok") ], [ "evil.pdf", sample_exe ], [ "empty.pdf", "" ] ]), "mixed.zip" ])

      expect(result.created.map(&:name)).to eq([ "ok.pdf" ])
      expect(result.refused).to contain_exactly(a_string_starting_with("mixed.zip / evil.pdf: "), a_string_starting_with("mixed.zip / empty.pdf: "))
    end

    it "keeps only the name of a file, never a path (a hostile archive cannot reach outside)" do
      result = call([ zip([ [ "../../etc/cron.d/x.pdf", sample_pdf("trav") ], [ "a/b/../../y.pdf", sample_pdf("dots") ] ]), "t.zip" ])

      expect(result.created.map(&:name)).to contain_exactly("x.pdf", "y.pdf")
    end

    it "leaves out what is only the system's litter" do
      litter = zip([ [ "real.pdf", sample_pdf("real") ], [ "__MACOSX/._real.pdf", "junk" ], [ ".DS_Store", "junk" ], [ "Thumbs.db", "junk" ], [ "folder/", "" ] ])

      result = call([ litter, "l.zip" ])

      expect(result.created.map(&:name)).to eq([ "real.pdf" ])
      expect(result.refused).to be_empty
    end

    it "does not unpack an archive inside an archive" do
      inner = zip([ [ "deep.pdf", sample_pdf("deep") ] ])

      result = call([ zip([ [ "inner.zip", inner ], [ "top.pdf", sample_pdf("top") ] ]), "outer.zip" ])

      expect(result.created.map(&:name)).to eq([ "top.pdf" ])
      expect(result.refused.join).to match(/archive inside an archive/i)
    end

    it "does not take a spreadsheet for an archive" do
      result = call([ sample_xlsx, "book.xlsx" ])

      expect(result.created.map(&:name)).to eq([ "book.xlsx" ])
    end

    it "refuses an archive with nothing in it" do
      result = call([ zip([ [ "folder/", "" ] ]), "empty.zip" ])

      expect(result.created).to be_empty
      expect(result.refused.join).to match(/no file/i)
    end

    it "refuses a damaged archive" do
      result = call([ "PK\x03\x04this is not really a zip".b, "broken.zip" ])

      expect(result.created).to be_empty
      expect(result.refused.join).to include("broken.zip")
    end

    it "does not create the same document twice, from two archives or from the archive and a loose file" do
      once = call([ archive, "a.zip" ], [ sample_pdf("one"), "loose.pdf" ])

      expect(once.created.size).to eq(3)
      expect(once.refused.join).to include("loose.pdf")
    end
  end

  describe "the limits (the settings of Rails.configuration.x.document_archive_limits)" do
    around do |example|
      previous = Rails.configuration.x.document_archive_limits
      example.run
    ensure
      Rails.configuration.x.document_archive_limits = previous
    end

    def limits(**values) = Rails.configuration.x.document_archive_limits = { files: 50, bytes: 100.megabytes, ratio: 100 }.merge(values)

    it "unpacks up to the limit and reports the rest" do
      limits(files: 2)
      big = zip((1..4).map { |i| [ "f#{i}.pdf", sample_pdf("file #{i}") ] })

      result = call([ big, "many.zip" ])

      expect(result.created.size).to eq(2)
      expect(result.refused.size).to eq(2)
      expect(result.refused.join).to match(/limit of 2 files/i)
    end

    it "refuses an archive that would be too big once unpacked, before reading it" do
      limits(bytes: 1.kilobyte)
      big = zip([ [ "a.pdf", sample_pdf("a" * 3000) ] ])

      result = call([ big, "big.zip" ])

      expect(result.created).to be_empty
      expect(result.refused.join).to match(/larger than 1 KB/i)
    end

    it "refuses a file that is far too compressed to be honest (a decompression bomb), without unpacking it" do
      limits(ratio: 10)
      bomb = zip([ [ "bomb.pdf", "%PDF-1.4\n" + ("0" * 2_000_000) ] ])

      result = call([ bomb, "bomb.zip" ])

      expect(result.created).to be_empty
      expect(result.refused.join).to match(/compress/i)
    end

    it "has sane defaults: 50 files, 100 MB, 100:1" do
      expect(Rails.configuration.x.document_archive_limits).to eq(files: 50, bytes: 100.megabytes, ratio: 100)
    end
  end

  describe "an archive that asks for a password" do
    it "is refused with a clear message" do
      encrypted = Dir.mktmpdir do |dir|
        File.write("#{dir}/a.txt", "secret")
        system("zip", "-q", "-P", "pw", "#{dir}/e.zip", "a.txt", chdir: dir) ? File.binread("#{dir}/e.zip") : nil
      end
      skip "the zip tool is not installed here" unless encrypted

      result = call([ encrypted, "locked.zip" ])

      expect(result.created).to be_empty
      expect(result.refused.join).to match(/password|encrypted/i)
    end
  end
end

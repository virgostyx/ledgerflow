# What an external auditor is shown of a document (F03): the file with their name across it, never the file as it is.
# A PDF is stamped with Ghostscript (the mark is an outline, so nothing underneath is hidden, and the name also goes in
# the file's own properties), a PNG or JPEG with ImageMagick. Anything else cannot be marked and is refused: the caller
# never serves an unmarked file when it should have been marked. Programs are run without a shell, with a time limit,
# in -dSAFER mode, on files this class has written itself; the name is reduced to a few harmless characters first
# (it ends up inside a PostScript string and an image annotation).
class Accounting::WatermarkFile
  MAX_LABEL = 60
  PDF = "application/pdf".freeze
  IMAGES = { "image/png" => "png", "image/jpeg" => "jpeg" }.freeze

  class Unsupported < StandardError; end
  class Unavailable < StandardError; end

  def self.markable?(content_type) = content_type == PDF || IMAGES.key?(content_type)

  def self.call(bytes, content_type, name)
    raise Unsupported, "cannot mark #{content_type}" unless markable?(content_type)

    label = safe_label(name)
    content_type == PDF ? pdf(bytes, label) : image(bytes, IMAGES.fetch(content_type), label)
  rescue Accounting::ExternalCommand::Failed => e
    raise Unavailable, e.message
  end

  # Letters, digits, spaces and . , ' - only; accents removed; a bounded length; never blank.
  def self.safe_label(name)
    label = I18n.transliterate(name.to_s).gsub(/[^A-Za-z0-9 .,'\-]/, " ").squish.first(MAX_LABEL).strip
    label.presence || "Viewer"
  end

  def self.pdf(bytes, label)
    Dir.mktmpdir("watermark") do |dir|
      input = File.join(dir, "in.pdf")
      output = File.join(dir, "out.pdf")
      File.binwrite(input, bytes)
      Accounting::ExternalCommand.run("gs", "-q", "-dBATCH", "-dNOPAUSE", "-dSAFER", "-sDEVICE=pdfwrite", "-sOutputFile=#{output}", "-c", pdf_program(label), "-f", input)
      raise Unavailable, "no output" unless File.size?(output)

      File.binread(output)
    end
  end

  # At the end of every page: the name, centred and slanted, in outline (light grey), whatever the page size.
  def self.pdf_program(label)
    "[ /Subject (Viewed by #{label}) /DOCINFO pdfmark " \
      "<< /EndPage { exch pop 2 ne { gsave currentpagedevice /PageSize get aload pop 2 div exch 2 div exch translate 35 rotate " \
      "/Helvetica-Bold findfont 48 scalefont setfont 0.45 setgray 0.8 setlinewidth " \
      "(#{label}) dup stringwidth pop 2 div neg 0 moveto true charpath stroke grestore true } { false } ifelse } >> setpagedevice"
  end

  # `png:` / `jpeg:` force the decoder: the content decides nothing.
  def self.image(bytes, coder, label)
    Dir.mktmpdir("watermark") do |dir|
      input = File.join(dir, "in")
      output = File.join(dir, "out")
      File.binwrite(input, bytes)
      width = Accounting::ExternalCommand.run("identify", "-format", "%w", "#{coder}:#{input}").to_i
      raise Unavailable, "unreadable image" unless width.positive?

      Accounting::ExternalCommand.run("convert", "#{coder}:#{input}", "-gravity", "center", "-font", "Helvetica-Bold", "-pointsize", [ width / 12, 12 ].max.to_s,
                                      "-fill", "none", "-stroke", "gray(45%)", "-strokewidth", "1", "-annotate", "35x35+0+0", label, "#{coder}:#{output}")
      raise Unavailable, "no output" unless File.size?(output)

      File.binread(output)
    end
  end

  private_class_method :pdf, :pdf_program, :image
end

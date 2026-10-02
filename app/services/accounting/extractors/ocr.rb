# Optical character recognition with the local `tesseract` (nothing leaves this server). A picture is read as it is; a
# scanned PDF is first turned into pictures with `pdftoppm`. Reads in the installed languages among French, Dutch
# and English. The confidence is tesseract's mean word confidence: below MIN_CONFIDENCE, nothing is worth keeping.
# Commands are run without a shell, with a time limit, and only on files this class has written itself.
class Accounting::Extractors::Ocr
  MIN_CONFIDENCE = 60
  MAX_PAGES = 10
  TIMEOUT = 90
  # 4 = one column of text of variable sizes: what an invoice is. (The automatic mode 3 splits a sparse page into pieces.)
  PAGE_SEGMENTATION = "4".freeze
  LANGUAGES = %w[fra nld eng].freeze
  EXTENSIONS = { "image/png" => "png", "image/jpeg" => "jpg", "image/tiff" => "tif" }.freeze

  def self.call(bytes, content_type) = new(bytes, content_type).call

  # The installed languages among the wanted ones; English at least.
  def self.languages
    @languages ||= begin
      installed = `tesseract --list-langs 2>/dev/null`.lines.map(&:strip)
      (LANGUAGES & installed).presence || %w[eng]
    end
  end

  def initialize(bytes, content_type)
    @bytes = bytes
    @content_type = content_type
  end

  def call
    Dir.mktmpdir("ocr") do |dir|
      pages = page_images(dir).first(MAX_PAGES).map { |image| read(image) }
      words = pages.flat_map { |page| page[:confidences] }
      Accounting::Extractors::Result.new(text: pages.map { |page| page[:text] }.join("\f"), method: "ocr",
                                         confidence: words.empty? ? nil : (words.sum / words.size).round)
    end
  end

  private

  def page_images(dir)
    if @content_type == "application/pdf"
      File.binwrite(File.join(dir, "in.pdf"), @bytes)
      run("pdftoppm", "-png", "-r", "200", "-l", MAX_PAGES.to_s, File.join(dir, "in.pdf"), File.join(dir, "page"))
      Dir[File.join(dir, "page*.png")].sort
    else
      path = File.join(dir, "in.#{EXTENSIONS.fetch(@content_type) { raise Accounting::Extractors::Unreadable, "not a picture" }}")
      File.binwrite(path, @bytes)
      [ path ]
    end
  end

  # => { text:, confidences: [word confidences] }
  def read(image)
    out = run("tesseract", image, "stdout", "-l", self.class.languages.join("+"), "--psm", PAGE_SEGMENTATION, "tsv")
    lines = Hash.new { |hash, key| hash[key] = [] }
    confidences = []
    out.lines.drop(1).each do |row|
      level, _page, block, paragraph, line, _word, _left, _top, _width, _height, conf, text = row.chomp.split("\t", 12)
      next unless level == "5" && text.to_s.strip.present? && conf.to_f >= 0

      lines[[ block, paragraph, line ]] << text.strip
      confidences << conf.to_f
    end
    { text: lines.values.map { |words| words.join(" ") }.join("\n"), confidences: confidences }
  end

  def run(*command)
    Accounting::ExternalCommand.run(*command, timeout: TIMEOUT)
  rescue Accounting::ExternalCommand::Failed => e
    raise Accounting::Extractors::Unreadable, e.message
  end
end

# Cuts a text into passages of about 500 to 800 tokens (A06), each attached to the title of its section, with a short overlap between two passages of the same section so that a rule cut in two is
# found from either side. A title is a Markdown heading or a numbered line ("2.1 Prepayments"). A passage that is mostly figures and bars (a table) or a few words (a footnote) is marked low quality:
# the search puts it after the others.
module Knowledge::Chunker
  TARGET = 2400
  HARD_MAX = 3200
  OVERLAP = 300
  HEADING = /\A(?:\#{1,6}\s+(?<md>.+)|(?<num>\d+(?:\.\d+)*\.?\s+\p{Lu}[^.!?]{2,90}))\z/

  Passage = Data.define(:section, :content, :quality)

  def self.call(text)
    passages = []
    section = nil
    pending = []
    paragraph = []
    close_paragraph = -> { pending << paragraph.join("\n") if paragraph.any?; paragraph = [] }
    flush = -> { close_paragraph.call; passages.concat(pack(pending, section)) if pending.any?; pending = [] }
    text.to_s.gsub("\r\n", "\n").lines.map(&:strip).each do |line|
      if line.empty?
        close_paragraph.call
      elsif (heading = line.match(HEADING))
        flush.call
        section = (heading[:md] || heading[:num]).strip
      else
        paragraph << line
      end
    end
    flush.call
    passages
  end

  def self.pack(blocks, section)
    pieces = blocks.flat_map { |block| block.length > HARD_MAX ? split_long(block) : [ block ] }
    chunks = []
    current = +""
    pieces.each do |piece|
      if current.present? && current.length + piece.length + 2 > TARGET
        chunks << current
        current = tail(current)
      end
      current << "\n\n" if current.present?
      current << piece
    end
    chunks << current if current.present? && (chunks.empty? || current.length > OVERLAP + 20)
    chunks.map { |content| Passage.new(section: section, content: content.strip, quality: quality_of(content)) }
  end
  private_class_method :pack

  def self.split_long(block)
    block.scan(/.{1,#{TARGET}}(?:\s+|\z)/m).map(&:strip).reject(&:empty?)
  end
  private_class_method :split_long

  # The end of a passage, from a word boundary, repeated at the start of the next.
  def self.tail(content)
    cut = content[-OVERLAP..] || content
    cut.sub(/\A\S*\s+/, "")
  end
  private_class_method :tail

  def self.quality_of(content)
    letters = content.scan(/\p{L}/).size
    letters < content.length * 0.5 || content.split.size < 6 ? "low" : "normal"
  end
  private_class_method :quality_of
end

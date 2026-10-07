# A passage of a knowledge document (A06): about 500 to 800 tokens, with its section title, and the full text index built from it (see Knowledge::Ingest).
class Knowledge::Chunk < ApplicationRecord
  self.table_name = "knowledge_chunks"

  CONFIGS = { "fr" => "french", "nl" => "dutch", "en" => "english" }.freeze
  EXCERPT_LENGTH = 1200

  belongs_to :document, class_name: "Knowledge::Document"

  validates :content, presence: true
  validates :quality, inclusion: { in: %w[normal low] }
  validates :config, inclusion: { in: CONFIGS.values }

  def ref = Agent::Refs.build("kb", "doc-#{document_id}", "p-#{position}")

  # At most EXCERPT_LENGTH characters: the whole passage when it fits, otherwise the stretch of it that holds the most of the words searched.
  def excerpt(words = [])
    return content if content.length <= EXCERPT_LENGTH

    starts = [ 0 ] + content.enum_for(:scan, /(?<=[.!?\n]) /).map { Regexp.last_match.end(0) }
    best = starts.max_by do |start|
      window = content[start, EXCERPT_LENGTH].downcase
      [ words.count { |word| window.include?(word) }, -start ]
    end
    text = content[best, EXCERPT_LENGTH].rstrip
    "#{'…' if best.positive?}#{text}#{'…' if best + EXCERPT_LENGTH < content.length}"
  end
end

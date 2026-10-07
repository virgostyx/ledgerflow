# The legal references of a text (A06): an article, a law, a royal decree, a circular. The agent may quote one only if a passage it was given, or the person who asked, contains it: a reference
# from the model's memory is a reference nobody checked. Each is reduced to a key (`article:45bis`, `law:1992`, `circular:2021/c/45`) so that "Article 45 bis" and "art. 45bis" are the same, and the key is what is compared.
# Dates and rates are not checked here: a rule's date or rate is only safe because the prompt says to quote it from a passage (see A06.md).
module Agent::LegalReferences
  SUFFIX = /(?:\s?(?:bis|ter|quater|quinquies))?/i
  ARTICLE = /\b(?:art(?:icles?|ikels?|icle)?|artt?)\.?\s*(\d+(?:[.:]\d+)*#{SUFFIX.source})/i
  KINDS = { "law" => /(?:loi|wet|law)/i, "decree" => /(?:arr[êe]t[ée]\s+royal|koninklijk\s+besluit|royal\s+decree|(?-i:AR|KB))/i, "circular" => /(?:circulaire|omzendbrief|circular)/i }.freeze
  # What follows the name of a text: "du 15 mars 2007", "of 12/05/1992", "2021/C/45", "1992". Only a date or a number right after the name, so that a sentence that merely mentions a year is not taken for a reference.
  YEAR = /(?:\s+(?:du|van|of|de|dd\.?|from))?\s+(?:\d{1,2}(?:er)?\s+\p{L}+\s+|\d{1,2}[\/.-]\d{1,2}[\/.-])?(\d{4}\/[A-Za-z]\/\d+|(?:19|20)\d{2})\b/

  Match = Data.define(:key, :position, :length)

  # => [Match], in order of appearance.
  def self.matches(text)
    text = text.to_s
    found = text.to_enum(:scan, ARTICLE).map { Regexp.last_match }.map { |m| Match.new("article:#{m[1].downcase.delete(' ')}", m.begin(0), m[0].length) }
    KINDS.each do |kind, words|
      text.to_enum(:scan, /\b#{words.source}\b#{YEAR.source}/i).map { Regexp.last_match }.each { |m| found << Match.new("#{kind}:#{m[1].downcase}", m.begin(0), m[0].length) }
    end
    found.sort_by(&:position)
  end

  def self.keys(text) = matches(text).map(&:key).uniq
end

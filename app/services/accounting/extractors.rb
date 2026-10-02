# What a document can be read with (F03). Each extractor takes the bytes of a file and returns a Result; none of them
# sends anything outside this server (OCR is the local `tesseract`), none resolves an external entity, none executes
# what it reads. `Unreadable` is raised for a file that cannot be read at all (damaged, protected, not what it says).
module Accounting::Extractors
  Result = Struct.new(:text, :method, :confidence, :fields, keyword_init: true)

  class Unreadable < StandardError; end
end

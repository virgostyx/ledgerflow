# The contract of a bank statement parser (F02): CODA today, CAMT.053 later, without touching what imports and matches.
#
#   Banking::SomeParser.call(bytes_or_text, **options) => Banking::ParseResult
#
# Pure: nothing is written. A parser either returns statements (success) or the list of the faulty lines (no statement:
# a file is imported whole or not at all).
module Banking::StatementParser
  def self.included(base) = base.extend(ClassMethods)

  module ClassMethods
    def call(input, **options) = new.call(input, **options)
  end

  def call(_input, **_options) = raise(NotImplementedError, "#{self.class} must implement #call")
end

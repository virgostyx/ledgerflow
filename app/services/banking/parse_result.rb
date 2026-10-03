# What a statement parser returns: the statements, or the errors that refused the file; warnings never refuse it.
Banking::ParseResult = Struct.new(:statements, :errors, :warnings, keyword_init: true) do
  def success? = errors.empty?
end

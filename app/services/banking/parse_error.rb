# One faulty line of a file (1-based), with what is wrong with it.
Banking::ParseError = Struct.new(:line, :text, keyword_init: true) do
  def message = "line #{line}: #{text}"
end

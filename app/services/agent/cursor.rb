# The cursor of a list tool (A02): the offset of the next row, in an opaque string. The model passes it back as it got it; one it made up is turned away.
module Agent::Cursor
  def self.encode(offset) = Base64.urlsafe_encode64({ "o" => offset }.to_json, padding: false)

  def self.decode(cursor)
    return 0 if cursor.blank?

    offset = JSON.parse(Base64.urlsafe_decode64(cursor)).fetch("o")
    Integer(offset).positive? ? Integer(offset) : raise(ArgumentError)
  rescue ArgumentError, JSON::ParserError, KeyError, TypeError
    raise Agent::ToolError.new("invalid_arguments", "cursor is not one this tool gave: use the next_cursor of its previous answer.")
  end
end

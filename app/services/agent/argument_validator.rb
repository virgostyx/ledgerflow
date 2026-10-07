# Checks what the model passed to a tool against the tool's input schema (A02/A03): only the arguments the schema names (so a company_id, an entity or a user
# is turned away), the required ones, the types, the lists, the ranges and the dates. The schema is the one sent to the model; the check is made here again because the model's
# arguments are not trusted.
module Agent::ArgumentValidator
  def self.problems(schema, args)
    args = args.to_h.stringify_keys
    properties = schema.fetch(:properties, {}).transform_keys(&:to_s)
    problems = (args.keys - properties.keys).map { |key| "#{key} is not an argument of this tool" }
    problems += Array(schema[:required]).map(&:to_s).reject { |key| args.key?(key) }.map { |key| "#{key} is required" }
    args.slice(*properties.keys).each { |key, value| problems.concat(check(key, value, properties[key].deep_symbolize_keys)) }
    problems
  end

  def self.check(name, value, rule)
    case rule[:type]
    when "string"  then check_string(name, value, rule)
    when "integer" then check_integer(name, value, rule)
    when "boolean" then [ true, false ].include?(value) ? [] : [ "#{name} must be true or false" ]
    when "array"   then check_array(name, value, rule)
    else []
    end
  end
  private_class_method :check

  def self.check_string(name, value, rule)
    return [ "#{name} must be a string" ] unless value.is_a?(String)
    return [ "#{name} must be one of #{rule[:enum].join(', ')}" ] if rule[:enum] && !rule[:enum].include?(value)
    return [ "#{name} is too long (#{rule[:maxLength]} characters at most)" ] if rule[:maxLength] && value.length > rule[:maxLength]
    return [ "#{name} must be a date (YYYY-MM-DD)" ] if rule[:format] == "date" && !valid_date?(value)
    return [ "#{name} does not have the expected form" ] if rule[:pattern] && !value.match?(Regexp.new(rule[:pattern]))

    []
  end
  private_class_method :check_string

  def self.check_integer(name, value, rule)
    return [ "#{name} must be an integer" ] unless value.is_a?(Integer)
    return [ "#{name} must be between #{rule[:minimum]} and #{rule[:maximum]}" ] if (rule[:minimum] && value < rule[:minimum]) || (rule[:maximum] && value > rule[:maximum])

    []
  end
  private_class_method :check_integer

  def self.check_array(name, value, rule)
    return [ "#{name} must be a list" ] unless value.is_a?(Array)
    return [ "#{name} must have at least #{rule[:minItems]} item(s)" ] if rule[:minItems] && value.size < rule[:minItems]
    return [ "#{name} must have at most #{rule[:maxItems]} item(s)" ] if rule[:maxItems] && value.size > rule[:maxItems]

    value.each_with_index.flat_map { |item, index| check("#{name}[#{index}]", item, rule.fetch(:items, {})) }
  end
  private_class_method :check_array

  def self.valid_date?(value)
    value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.strptime(value, "%Y-%m-%d").iso8601 == value
  rescue Date::Error
    false
  end
  private_class_method :valid_date?
end

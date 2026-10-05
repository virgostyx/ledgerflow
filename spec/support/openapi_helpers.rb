# F13c: a small validator of an OpenAPI 3.1 document (its structure and its references), and of a JSON value against one of its schemas: enough to
# check the document we publish and that real answers keep to it. No dependency: the keywords the document uses are the ones handled.
module OpenapiHelpers
  SCHEMA_TYPES = %w[string integer number boolean array object null].freeze
  METHODS = %w[get post put patch delete].freeze

  def document_problems(doc)
    problems = []
    problems << "openapi must be 3.1.x" unless doc["openapi"].to_s.start_with?("3.1")
    problems << "info.title and info.version are required" unless doc.dig("info", "title") && doc.dig("info", "version")
    ids = []
    doc.fetch("paths").each do |path, item|
      problems << "#{path} must start with /" unless path.start_with?("/")
      placeholders = path.scan(/\{(\w+)\}/).flatten
      item.each do |method, op|
        problems << "#{path}: #{method} is not an HTTP method" unless METHODS.include?(method)
        label = "#{method.upcase} #{path}"
        problems << "#{label}: operationId is missing" unless op["operationId"]
        ids << op["operationId"]
        problems << "#{label}: no responses" if op["responses"].blank?
        op["responses"].each_key { |code| problems << "#{label}: status #{code} is not valid" unless code.match?(/\A[1-5]\d\d\z/) }
        params = Array(op["parameters"]).map { |p| p["$ref"] ? resolve(doc, p["$ref"], problems) : p }
        params.each { |p| problems << "#{label}: a parameter needs name, in and schema" unless p && p["name"] && p["in"] && p["schema"] }
        placeholders.each { |name| problems << "#{label}: path parameter #{name} is not declared" unless params.any? { |p| p && p["in"] == "path" && p["name"] == name && p["required"] == true } }
      end
    end
    problems << "operationIds are not unique" if ids.uniq.size != ids.size
    each_ref(doc) { |ref| resolve(doc, ref, problems) }
    each_schema(doc["components"]["schemas"]) { |schema| problems << "unknown type #{schema['type'].inspect}" unless (Array(schema["type"]) - SCHEMA_TYPES).empty? }
    problems << "the security scheme bearerAuth is missing" unless doc.dig("components", "securitySchemes", "bearerAuth")
    problems.uniq
  end

  def resolve(doc, ref, problems = [])
    node = ref.delete_prefix("#/").split("/").reduce(doc) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    problems << "reference #{ref} does not resolve" if node.nil?
    node
  end

  def each_ref(node, &block)
    case node
    when Hash then node.each { |k, v| k == "$ref" ? block.call(v) : each_ref(v, &block) }
    when Array then node.each { |v| each_ref(v, &block) }
    end
  end

  def each_schema(node, &block)
    case node
    when Hash
      block.call(node) if node.key?("type") && node["type"].is_a?(String) | node["type"].is_a?(Array)
      node.each_value { |v| each_schema(v, &block) }
    when Array then node.each { |v| each_schema(v, &block) }
    end
  end

  # => the ways the value does not keep to the schema (empty when it does)
  def schema_violations(doc, schema, value, at = "$")
    schema = resolve(doc, schema["$ref"]) while schema["$ref"]
    types = Array(schema["type"])
    return [ "#{at}: #{value.inspect} is none of #{types.join('|')}" ] if types.any? && types.none? { |t| type_ok?(t, value) }

    out = []
    out << "#{at}: #{value.inspect} is not in #{schema['enum'].inspect}" if schema["enum"] && !schema["enum"].include?(value)
    out << "#{at}: #{value.inspect} does not match #{schema['pattern']}" if schema["pattern"] && value.is_a?(String) && !value.match?(Regexp.new(schema["pattern"]))
    out << "#{at}: #{value.inspect} is not a date" if schema["format"] == "date" && value.is_a?(String) && !(Date.iso8601(value) rescue false)
    out << "#{at}: #{value.inspect} is not a date-time" if schema["format"] == "date-time" && value.is_a?(String) && !(Time.iso8601(value) rescue false)
    if value.is_a?(Hash)
      Array(schema["required"]).each { |name| out << "#{at}: #{name} is missing" unless value.key?(name) }
      (schema["properties"] || {}).each { |name, sub| out.concat(schema_violations(doc, sub, value[name], "#{at}.#{name}")) if value.key?(name) }
    elsif value.is_a?(Array) && schema["items"]
      value.each_with_index { |item, i| out.concat(schema_violations(doc, schema["items"], item, "#{at}[#{i}]")) }
    end
    out
  end

  def type_ok?(type, value)
    case type
    when "string" then value.is_a?(String)
    when "integer" then value.is_a?(Integer)
    when "number" then value.is_a?(Numeric)
    when "boolean" then [ true, false ].include?(value)
    when "array" then value.is_a?(Array)
    when "object" then value.is_a?(Hash)
    when "null" then value.nil?
    end
  end
end

RSpec.configure { |config| config.include OpenapiHelpers }

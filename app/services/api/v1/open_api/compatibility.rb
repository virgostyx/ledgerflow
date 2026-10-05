# F13c: what a change of the OpenAPI document breaks for the callers of a published version. Adding is allowed (a path, an optional parameter, a property
# of an answer, a status); removing or narrowing is not: a path or an operation gone, a parameter gone or made required, a response status gone, a property
# of an answer gone or of another type, an enum value of an answer gone, a property required in a request that was not. `breaking_changes(old, new)` => [String].
module Api::V1::OpenApi::Compatibility
  METHODS = %w[get post put patch delete].freeze

  def self.breaking_changes(old, new)
    changes = []
    old.fetch("paths").each do |path, item|
      new_item = new.fetch("paths")[path]
      next changes << "path #{path} was removed" unless new_item

      METHODS.each do |method|
        next unless item[method]
        next changes << "#{method.upcase} #{path} was removed" unless new_item[method]

        compare_operation("#{method.upcase} #{path}", item[method], new_item[method], old, new, changes)
      end
    end
    changes
  end

  def self.compare_operation(label, old_op, new_op, old_doc, new_doc, changes)
    old_params = resolve_all(old_op["parameters"], old_doc).index_by { |p| [ p["in"], p["name"] ] }
    new_params = resolve_all(new_op["parameters"], new_doc).index_by { |p| [ p["in"], p["name"] ] }
    old_params.each_key { |key| changes << "#{label}: parameter #{key.last} (#{key.first}) was removed" unless new_params.key?(key) }
    new_params.each { |key, param| changes << "#{label}: parameter #{key.last} (#{key.first}) became required" if param["required"] && !old_params.dig(key, "required") }

    old_op["responses"].each_key do |status|
      next changes << "#{label}: response #{status} was removed" unless new_op["responses"].key?(status)

      compare_schema("#{label} #{status}", schema_of(old_op["responses"][status], old_doc), schema_of(new_op["responses"][status], new_doc), old_doc, new_doc, changes, :response)
    end
    compare_schema("#{label} body", schema_of(old_op["requestBody"], old_doc), schema_of(new_op["requestBody"], new_doc), old_doc, new_doc, changes, :request) if old_op["requestBody"]
    changes << "#{label}: the scope changed from #{old_op['x-required-scope']} to #{new_op['x-required-scope']}" if old_op["x-required-scope"] != new_op["x-required-scope"]
  end

  def self.compare_schema(label, old_schema, new_schema, old_doc, new_doc, changes, direction)
    return unless old_schema
    return changes << "#{label}: the content was removed" unless new_schema

    old_schema, new_schema = deref(old_schema, old_doc), deref(new_schema, new_doc)
    old_types, new_types = Array(old_schema["type"]), Array(new_schema["type"])
    changes << "#{label}: type #{old_types.join('|')} became #{new_types.join('|')}" if direction == :response && old_types.any? && !(old_types - new_types).empty?
    changes << "#{label}: enum values removed (#{(old_schema['enum'] - new_schema['enum'].to_a).join(', ')})" if direction == :response && old_schema["enum"] && (old_schema["enum"] - new_schema["enum"].to_a).any?

    (old_schema["properties"] || {}).each do |name, property|
      next changes << "#{label}: property #{name} was removed" unless new_schema.dig("properties", name)

      compare_schema("#{label}.#{name}", property, new_schema["properties"][name], old_doc, new_doc, changes, direction)
    end
    if direction == :request
      (Array(new_schema["required"]) - Array(old_schema["required"])).each { |name| changes << "#{label}: property #{name} became required" }
    end
    compare_schema("#{label}[]", old_schema["items"], new_schema["items"], old_doc, new_doc, changes, direction) if old_schema["items"]
  end

  def self.schema_of(node, doc)
    return unless node

    node = deref(node, doc)
    node.dig("content", "application/json", "schema") || node.dig("content", "application/problem+json", "schema")
  end

  def self.deref(node, doc)
    node = lookup(node["$ref"], doc) while node.is_a?(Hash) && node["$ref"]
    node
  end

  def self.lookup(ref, doc) = ref.delete_prefix("#/").split("/").reduce(doc) { |memo, key| memo.fetch(key) }

  def self.resolve_all(parameters, doc) = Array(parameters).map { |p| deref(p, doc) }
end

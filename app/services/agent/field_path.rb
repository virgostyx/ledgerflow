# Reaches fields of a tool result by a path: "data.*.label" is the label of every element of the list "data" ("*" stands for each element of a list).
module Agent::FieldPath
  # Replaces, by the block's answer, the value at the path, in the hash it is given.
  def self.update(node, path, &block)
    key, *rest = path.is_a?(String) ? path.split(".") : path
    case node
    when Array then node.each { |item| update(item, rest, &block) } if key == "*"
    when Hash
      return unless node.key?(key)

      rest.empty? ? node[key] = yield(node[key]) : update(node[key], rest, &block)
    end
  end
end

# What a tool of the agent is (A02 grows this): a name, a description written for the model, a strict input schema, the permission it needs, and a `call`
# that reads through an existing service. A tool never writes to the books.
class Agent::Tools::Base
  class << self
    # A subclass keeps what its parent declared, unless it declares its own.
    %i[tool_name description permission input_schema].each do |attribute|
      define_method(attribute) do |value = nil|
        return instance_variable_set("@#{attribute}", value) if value

        instance_variable_get("@#{attribute}") || (superclass.public_send(attribute) if superclass.respond_to?(attribute))
      end
    end

    def definition = { name: tool_name, description: description, strict: true, input_schema: input_schema }
  end

  def call(_args, _context) = raise(NotImplementedError)
end

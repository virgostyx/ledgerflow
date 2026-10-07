# What a tool of the agent is (A02): a name, a description written for the model (when to use it, when not), a strict input schema, the permission it needs, and a `call`
# that reads through an existing service and answers in the Agent::ToolResult envelope. A tool never writes to the books, and never takes the entity or the person as an
# argument: they come from the context the server built.
class Agent::Tools::Base
  FIELD_CLASSES = %i[public_ref financial personal bank_identifier tax_identifier free_text].freeze

  class << self
    # A subclass keeps what its parent declared, unless it declares its own.
    %i[tool_name description permission input_schema tool_version field_classes].each do |attribute|
      define_method(attribute) do |value = nil|
        return instance_variable_set("@#{attribute}", value) if value

        instance_variable_get("@#{attribute}") || (superclass.public_send(attribute) if superclass.respond_to?(attribute))
      end
    end

    # The class of data of each field of the output, for the redactor of A04: { "data.*.name" => :personal }.
    def classify(fields)
      unknown = fields.values - FIELD_CLASSES
      raise ArgumentError, "unknown data class #{unknown.first}" if unknown.any?

      field_classes(fields)
    end

    # The fields of free text that may run longer than the usual cut (a passage of the knowledge base).
    def long_text(*paths)
      @long_text = paths if paths.any?
      @long_text || (superclass.long_text if superclass.respond_to?(:long_text)) || []
    end

    def definition = { name: tool_name, description: description, strict: true, input_schema: input_schema }

    # The arguments every list tool takes: a page size (never more than `max`) and the cursor of the next page.
    def paging(max: 100)
      { limit: { type: "integer", minimum: 1, maximum: max, description: "How many rows to return (default #{[ 25, max ].min})." },
        cursor: { type: "string", maxLength: 200, description: "The next_cursor of the previous answer, to read the following rows." } }
    end
  end

  def call(_args, _context) = raise(NotImplementedError)

  private

  # Rows of a relation (or an array) from the cursor, and the cursor of the page after, or nil at the end.
  def page(rows, args, default: 25, max: 100)
    offset = Agent::Cursor.decode(args["cursor"])
    limit = [ args["limit"] || default, max ].min
    chunk = rows.respond_to?(:offset) ? rows.offset(offset).limit(limit + 1).to_a : rows.drop(offset).first(limit + 1)
    [ chunk.first(limit), (Agent::Cursor.encode(offset + limit) if chunk.size > limit) ]
  end

  def fiscal_year_from(args)
    year = args["fiscal_year"]
    found = year ? Accounting::FiscalYear.find_by(year: year) : (Accounting::FiscalYear.current || Accounting::FiscalYear.order(:year).last)
    found || raise(Agent::ToolError.new("not_found", year ? "There is no fiscal year #{year} for this entity." : "This entity has no fiscal year yet."))
  end

  def date_arg(args, key, default) = args[key] ? Date.iso8601(args[key]) : default

  def money(amount) = Agent::ToolResult.money(amount)

  def forbid_journal!(context, journal_id)
    membership = UserEntity.current.find_by(user: context.user, entity: context.entity)
    raise Agent::ToolError.new("forbidden", Agent::ToolRegistry::FORBIDDEN["message"]) unless membership&.allows_journal?(journal_id)
  end
end

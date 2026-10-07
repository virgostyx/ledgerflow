# Exact arithmetic for the agent (A05): every sum, difference, share and change of an answer goes through here, never through the model's head. Decimals, not floats; rounded half up to the
# precision asked. The result has a reference of its own, so that it can be cited like any figure of a report.
class Agent::Tools::Calculate < Agent::Tools::Base
  OPERATIONS = %w[sum difference multiply ratio percentage change_percent].freeze
  TWO_VALUES = %w[difference multiply ratio percentage change_percent].freeze

  tool_name "calculate"
  description "Does an exact calculation on amounts the other tools gave: sum (of any number of values), difference (the first minus the second), multiply, ratio (the first divided by the second), " \
              "percentage (the first as a percentage of the second) and change_percent (from the first value to the second, in percent). Values are decimal strings such as \"1210.00\". " \
              "Use it for EVERY sum, difference, percentage or comparison you state: never compute an amount yourself. " \
              "Do not use it to get a figure from the books (use the report tools), and do not give it amounts that no tool gave."
  permission "agent.use"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[operation values],
               properties: { operation: { type: "string", enum: OPERATIONS },
                             values: { type: "array", minItems: 1, maxItems: 50, items: { type: "string", pattern: "^-?\\d{1,13}(\\.\\d{1,6})?$" }, description: "Decimal strings, copied from tool results." },
                             precision: { type: "integer", minimum: 0, maximum: 6, description: "Decimals of the result (default 2)." } }
  classify "data.*.operation" => :public_ref

  def call(args, _context)
    operation, strings, precision = args["operation"], args["values"], args["precision"] || 2
    values = strings.map { |string| BigDecimal(string) }
    raise Agent::ToolError.new("invalid_arguments", "#{operation} needs exactly two values.") if TWO_VALUES.include?(operation) && values.size != 2

    result = compute(operation, values).round(precision, half: :up)
    Agent::ToolResult.build(
      data: [ { "operation" => operation, "values" => strings, "precision" => precision, "result" => decimal(result, precision),
                "ref" => "calc:#{Digest::SHA256.hexdigest([ operation, *strings, precision ].join('|'))[0, 12]}" } ],
      filters_applied: { "operation" => operation, "precision" => precision }
    )
  end

  private

  def compute(operation, values)
    first, second = values
    case operation
    when "sum"            then values.sum(BigDecimal("0"))
    when "difference"     then first - second
    when "multiply"       then first * second
    when "ratio"          then divide(first, second)
    when "percentage"     then divide(first, second) * 100
    when "change_percent" then divide(second - first, first) * 100
    end
  end

  def divide(numerator, denominator)
    raise Agent::ToolError.new("invalid_arguments", "Cannot divide by zero.") if denominator.zero?

    numerator.div(denominator, 20)
  end

  # "0.33", "-150", "10000000000000.00": exactly `precision` decimals, written out (never 1.5e-2).
  def decimal(value, precision)
    whole, fraction = value.to_s("F").split(".")
    precision.zero? ? whole : "#{whole}.#{fraction.to_s.ljust(precision, '0')[0, precision]}"
  end
end

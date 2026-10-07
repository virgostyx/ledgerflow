# Takes out of what is about to leave for the language model what the entity does not allow to leave (A04). It works on the payload itself, just before the call, so that nothing
# reaches the provider that was not looked at: the system prompt, the earlier turns, the results of the tools and the question. What it does depends on the settings of the entity, class of
# data by class of data: sent as it is, masked (a person's name becomes PERSONNE_017, an IBAN keeps its last four characters, a VAT number becomes TVA_003) or never sent.
#
# Two passes: the fields a tool declared (its classes of data, A02), then a sweep of every text for what identifies someone, whatever the field: IBANs, national numbers, VAT numbers
# and the names of partners that are, or may be, natural persons. A partner whose nature is not known is treated as a person.
class Agent::Redactor
  Result = Data.define(:system, :messages, :stats)

  MONEY = /\A-?\d{1,13}\.\d{2}\z/
  DATE = /\A\d{4}-\d{2}-\d{2}\z/
  BLOCKED = "[blocked]".freeze
  MIN_NAME = 4

  def initialize(setting:, conversation:, registry: Agent::ToolRegistry.default)
    @setting = setting
    @conversation = conversation
    @registry = registry
    @stats = Hash.new { |hash, data_class| hash[data_class] = Hash.new(0) }
  end

  def pseudonyms = @conversation.pseudonym_table

  def redact(system:, messages:)
    @stats.clear
    tool_names = tool_names_in(messages)
    Result.new(system: scrub(system.to_s), messages: messages.deep_dup.map { |message| redact_message(message, tool_names) }, stats: @stats.transform_values(&:to_h))
  end

  # The text of a message of the person, for what it holds that must not leave as it is.
  def scrub(text)
    text = remove_secrets(text.to_s.dup)
    text = mask_ibans(text)
    text = mask_national_numbers(text)
    text = mask_vat_numbers(text)
    mask_names(text)
  end

  private

  def mode(data_class) = @setting.mode_for(data_class)
  def count(data_class, how) = @stats[data_class.to_s][how] += 1

  def tool_names_in(messages)
    messages.flat_map { |message| Array(message[:content]).select { |block| block.is_a?(Hash) && block[:type].to_s == "tool_use" } }.to_h { |block| [ block[:id], block[:name] ] }
  end

  def redact_message(message, tool_names)
    content = message[:content]
    return message.merge(content: scrub(content)) if content.is_a?(String)

    message.merge(content: content.map { |block| redact_block(block, tool_names) })
  end

  def redact_block(block, tool_names)
    case block[:type].to_s
    when "text"        then block.merge(text: scrub(block[:text]))
    when "tool_result" then block.merge(content: redact_result(tool_names[block[:tool_use_id]], block[:content]))
    else block
    end
  end

  # The result of a tool, a JSON text: its declared fields by their class, then every value for what identifies someone.
  def redact_result(tool_name, content)
    parsed = JSON.parse(content)
    tool = @registry.tool(tool_name)
    tool&.field_classes.to_h.each { |path, data_class| Agent::FieldPath.update(parsed, path) { |value| apply_class(data_class, value) } }
    parsed = sweep(parsed)
    parsed.to_json
  rescue JSON::ParserError
    scrub(content)
  end

  def apply_class(data_class, value)
    return value unless value.is_a?(String)

    case data_class
    when :personal        then person(value)
    when :bank_identifier then bank_identifier(value)
    when :tax_identifier  then tax_identifier(value)
    when :free_text       then free_text(value)
    when :public_ref      then mode(:public_ref) == "send" ? value : (count(:public_ref, "blocked"); BLOCKED)
    else value
    end
  end

  # A company's name goes as it is, masked or not; but a class the entity does not let go does not go: no name at all, a company's included.
  def person(value)
    return blocked(:personal) if mode(:personal) == "block"
    return value if company_names.include?(value.strip.downcase) || mode(:personal) == "send"

    count(:personal, "masked")
    pseudonyms.token_for(value, "person")
  end

  def bank_identifier(value)
    case mode(:bank_identifier)
    when "send" then value
    when "mask" then (count(:bank_identifier, "masked"); "…#{value.delete(' ')[-4..]}")
    else blocked(:bank_identifier)
    end
  end

  def tax_identifier(value)
    case mode(:tax_identifier)
    when "send" then value
    when "mask" then (count(:tax_identifier, "masked"); pseudonyms.token_for(value, "tax_identifier"))
    else blocked(:tax_identifier)
    end
  end

  def free_text(value) = mode(:free_text) == "block" ? blocked(:free_text) : value

  def blocked(data_class) = blocked_text(data_class, BLOCKED)
  def blocked_text(data_class, text) = (count(data_class, "blocked"); text)

  # Every value of a result, whatever its field: what identifies someone is swept; money and dates are held back when the entity does not let figures go.
  def sweep(node)
    case node
    when Hash   then node.to_h { |key, value| [ key, key == "ref" && mode(:public_ref) != "send" ? blocked(:public_ref) : sweep(value) ] }
    when Array  then node.map { |value| sweep(value) }
    when String then financial?(node) && mode(:financial) != "send" ? blocked(:financial) : scrub(node)
    else node
    end
  end

  def financial?(text) = text.match?(MONEY) || text.match?(DATE)

  # A bank card number and a password do not go, whatever the settings.
  def remove_secrets(text)
    text = text.gsub(Agent::Identifiers::CARD) { |raw| Agent::Identifiers.card?(raw) ? blocked_text(:secret, "[card number blocked]") : raw }
    text.gsub(Agent::SensitiveInput::PASSWORD) { |raw| blocked_text(:secret, "#{raw[/\A\S+\s*[:=]/]} [secret blocked]") }
  end

  def mask_ibans(text)
    return text if mode(:bank_identifier) == "send"

    Agent::Identifiers.ibans(text).each do |raw, compact|
      text = text.sub(raw, mode(:bank_identifier) == "mask" ? "IBAN …#{compact[-4..]}" : "[IBAN blocked]")
      count(:bank_identifier, mode(:bank_identifier) == "mask" ? "masked" : "blocked")
    end
    text
  end

  def mask_national_numbers(text)
    return text if mode(:personal) == "send"

    text.gsub(Agent::Identifiers::NATIONAL_NUMBER) do |raw|
      next raw unless Agent::Identifiers.national_number?(raw)

      count(:personal, mode(:personal) == "mask" ? "masked" : "blocked")
      mode(:personal) == "mask" ? "[national number]" : "[national number blocked]"
    end
  end

  def mask_vat_numbers(text)
    return text if mode(:tax_identifier) == "send"

    [ Agent::Identifiers::BELGIAN_VAT, Agent::Identifiers::COMPANY_NUMBER, Agent::Identifiers::FOREIGN_VAT ].each do |pattern|
      text = text.gsub(pattern) do |raw|
        next raw if pattern != Agent::Identifiers::FOREIGN_VAT && !Agent::Identifiers.belgian_company_number?(raw)

        next blocked_text(:tax_identifier, "[VAT blocked]") unless mode(:tax_identifier) == "mask"

        count(:tax_identifier, "masked")
        pseudonyms.token_for(raw, "tax_identifier")
      end
    end
    text
  end

  def mask_names(text)
    return text if mode(:personal) == "send" || person_pattern.nil?

    text.gsub(person_pattern) do |raw|
      next raw if company_names.include?(raw.downcase) && mode(:personal) != "block"

      mode(:personal) == "mask" ? (count(:personal, "masked"); pseudonyms.token_for(raw, "person")) : (count(:personal, "blocked"); "[name blocked]")
    end
  end

  # The names of the partners that are natural persons or may be (not known), and those that are companies (left as they are).
  def partners
    @partners ||= Accounting::Partner.limit(20_000).pluck(:name, :is_natural_person)
  end

  def company_names = @company_names ||= partners.select { |_, natural| natural == false }.map { |name, _| name.to_s.strip.downcase }.to_set

  def person_pattern
    return @person_pattern if defined?(@person_pattern)

    names = partners.reject { |_, natural| natural == false && mode(:personal) != "block" }.map { |name, _| name.to_s.strip }.select { |name| name.length >= MIN_NAME }.uniq.sort_by { |name| -name.length }
    @person_pattern = names.empty? ? nil : Regexp.union(names.map { |name| /(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i })
  end
end

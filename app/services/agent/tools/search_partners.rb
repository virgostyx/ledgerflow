# Finds customers and suppliers by a word of their name, VAT number or city (A02). It gives who they are, never their bank details.
class Agent::Tools::SearchPartners < Agent::Tools::Base
  tool_name "search_partners"
  description "Searches the customers and suppliers of this entity by a word of the name, the VAT number or the city: returns the name, the type, the VAT number, the city and the country. " \
              "Use it to identify a customer or a supplier (and tell homonyms apart) before reading what they owe or are owed. " \
              "Do not use it for amounts or for bank details: use the aged balance or the ledger."
  permission "records.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[q],
               properties: { q: { type: "string", maxLength: 60, description: "A word of the name, the VAT number or the city." },
                             partner_type: { type: "string", enum: %w[customer supplier], description: "Only customers or only suppliers (those who are both match either)." },
                             include_inactive: { type: "boolean", description: "Also return archived partners (default false)." } }.merge(paging(max: 50))
  classify "data.*.name" => :personal, "data.*.vat_number" => :tax_identifier, "data.*.city" => :public_ref, "data.*.country" => :public_ref

  def call(args, _context)
    partners = Accounting::Partner.search(args["q"], "name", "vat_number", "city").order(:name)
    partners = partners.active unless args["include_inactive"]
    partners = args["partner_type"] == "customer" ? partners.customers : partners.suppliers if args["partner_type"]
    rows, next_cursor = page(partners, args, default: 25, max: 50)
    Agent::ToolResult.build(
      data: rows.map { |partner| { "name" => partner.name, "type" => partner.partner_type, "vat_number" => partner.vat_number, "city" => partner.city, "country" => partner.country,
                                   "active" => partner.active, "ref" => Agent::Refs.build("partner", partner.id) } },
      filters_applied: { "q" => args["q"], "partner_type" => args["partner_type"], "include_inactive" => args["include_inactive"] == true }.compact, next_cursor: next_cursor
    )
  end
end

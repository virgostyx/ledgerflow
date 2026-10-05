# F13a: customers and suppliers from a file. A partner already there (same external reference, VAT number or name) is skipped, never
# updated: an import adds, it does not overwrite.
class Imports::Kinds::Partners < Imports::Kind
  FIELDS = { "name" => true, "type" => true, "vat_number" => false, "email" => false, "phone" => false, "street" => false, "zip" => false,
             "city" => false, "country" => false, "iban" => false, "bic" => false, "payment_terms_days" => false, "external_ref" => false,
             "language" => false }.freeze
  ATTRIBUTES = (FIELDS.keys - %w[type name]).freeze

  def analyze
    analysis = Imports::Analysis.blank
    analysis.read = @table.rows.size
    return analysis unless check_mapping!(analysis)

    seen = existing_keys
    @table.rows.each_with_index do |row, i|
      line = @table.lines[i]
      name = cell(row, "name")
      type = cell(row, "type")&.downcase
      next analysis.refuse(name, line, "the name is missing") unless name
      next analysis.refuse(name, line, "the type \"#{type}\" is not customer, supplier or both") unless Accounting::Partner.partner_types.key?(type)

      attrs = ATTRIBUTES.index_with { |field| cell(row, field) }.compact.merge("name" => name, "partner_type" => type)
      keys = [ attrs["external_ref"], normalise_vat(attrs["vat_number"]), name.downcase ].compact
      next analysis.skipped << { ref: name, message: "already there" } if keys.any? { |k| seen.include?(k) }

      partner = Accounting::Partner.new(attrs)
      next analysis.refuse(name, line, partner.errors.full_messages.to_sentence) unless partner.valid?

      seen.merge(keys)
      analysis.items << attrs
    end
    analysis
  end

  def self.write(items, batch:, user:)
    created = 0
    refused = []
    items.each do |attrs|
      ApplicationRecord.transaction(requires_new: true) { Accounting::Partner.create!(attrs.merge("import_batch_id" => batch.id)) && created += 1 }
    rescue ActiveRecord::RecordInvalid => e
      refused << { ref: attrs["name"], lines: [], message: e.message }
    end
    { created: created, refused: refused }
  end

  private

  def existing_keys
    Accounting::Partner.pluck(:external_ref, :vat_number, :name).flat_map { |ref, vat, name| [ ref, normalise_vat(vat), name.downcase ] }.compact.to_set
  end

  def normalise_vat(vat) = vat&.delete(". ")&.upcase.presence
end

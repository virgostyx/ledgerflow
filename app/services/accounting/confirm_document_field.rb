# A person confirms (or corrects) a field proposed from a document (F03). Until then it is only a proposal; once
# confirmed it is kept through any new extraction. The value is checked for its kind (amount, date, IBAN, VAT number,
# structured communication, partner of this entity), and the change is audited with what was proposed and what was
# confirmed. A document frozen by a validated entry takes no change.
class Accounting::ConfirmDocumentField
  FIELDS = %w[supplier_partner_id invoice_number invoice_date due_date subtotal vat_amount total currency iban supplier_vat structured_communication].freeze
  AMOUNTS = %w[subtotal vat_amount total].freeze
  DATES = %w[invoice_date due_date].freeze

  def self.call(document:, field:, value:, user:)
    ctx = LightService::Context.make(document: document)
    return refuse(ctx, "unknown_field") unless FIELDS.include?(field.to_s)
    return refuse(ctx, "frozen") if document.locked?

    clean = clean(field.to_s, value.to_s.strip)
    return refuse(ctx, "bad_value") if clean.nil?

    extraction = document.extracted_data["extraction"] ||= {}
    fields = extraction["fields"] ||= {}
    previous = fields[field.to_s]
    fields[field.to_s] = (previous || { "snippet" => nil, "page" => nil, "confidence" => "high" })
                         .merge("value" => clean, "confirmed" => true, "confirmed_by" => user.id, "confirmed_at" => Time.current.iso8601)
    ApplicationRecord.transaction do
      document.update_columns(extracted_data: document.extracted_data, updated_at: Time.current)
      Accounting::AuditLog.record!(auditable: document, action: "document_field_confirm", user: user,
                                   payload: { field: field.to_s, from: previous&.dig("value"), to: clean })
    end
    ctx
  end

  # The value in its canonical form, or nil when it is not a valid one.
  def self.clean(field, value)
    return nil if value.blank?

    if AMOUNTS.include?(field)
      amount = Accounting::DocumentFieldParser.parse_amount(value)
      format("%.2f", amount) if amount
    elsif DATES.include?(field)
      Accounting::DocumentFieldParser.parse_date(value)
    else
      clean_identifier(field, value)
    end
  end

  def self.clean_identifier(field, value)
    case field
    when "iban" then Accounting::Iban.normalize(value) if Accounting::Iban.valid?(value)
    when "supplier_vat" then vat(value)
    when "structured_communication" then communication(value)
    when "currency" then value.upcase if value.match?(/\A[A-Za-z]{3}\z/)
    when "supplier_partner_id" then Accounting::Partner.find_by(id: value)&.id
    else value.first(64)
    end
  end

  def self.vat(value)
    number = value.upcase.gsub(/[\s.]/, "")
    number if number.match?(/\A[A-Z]{2}[A-Z0-9]{2,12}\z/) && (!number.start_with?("BE") || Accounting::BelgianVatNumber.valid?(number))
  end

  def self.communication(value)
    digits = Accounting::StructuredCommunication.extract(value)
    "+++#{digits[0, 3]}/#{digits[3, 4]}/#{digits[7, 5]}+++" if digits
  end

  def self.refuse(ctx, key) = ctx.tap { |c| c.fail!(I18n.t("documents.errors.field_#{key}")) }

  private_class_method :clean_identifier, :vat, :communication, :refuse
end

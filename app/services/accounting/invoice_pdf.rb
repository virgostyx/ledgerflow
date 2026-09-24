# Renders a customer invoice or credit note as a PDF (English only). The issuer comes from the current entity,
# the payment details from its first active bank account.
# ponytail: Prawn's built-in Helvetica only draws Windows-1252, so other characters print as "?"; embed a TTF font
# if partner names outside Western Europe matter.
class Accounting::InvoicePdf
  REVERSE_CHARGE = "VAT reverse charge: VAT to be accounted for by the customer".freeze
  # Generic wording, no Code TVA article on purpose: to be validated by an accountant.
  LEGAL_MENTIONS = {
    "intracom_goods"              => "Intra-community supply, VAT exempt",
    "intracom_services"           => REVERSE_CHARGE,
    "construction_reverse_charge" => REVERSE_CHARGE,
    "export"                      => "Export, VAT exempt",
    "exempt"                      => "VAT exempt"
  }.freeze
  FRANCHISE_MENTION = "VAT exemption for small businesses".freeze

  GREY = "666666".freeze

  def initialize(invoice)
    @invoice = invoice
    @entity  = ActsAsTenant.current_tenant || invoice.entity
    @bank    = Accounting::BankAccount.active.order(:id).first
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: 40, info: { Title: title_with_number })
    pdf.font "Helvetica"
    header(pdf)
    customer(pdf)
    lines_table(pdf)
    totals(pdf)
    payment(pdf)
    legal_mentions(pdf)
    footer(pdf)
    pdf.render
  end

  private

  attr_reader :invoice, :entity, :bank

  def credit_note? = invoice.credit_note?

  def title = credit_note? ? "Credit note" : "Invoice"

  def title_with_number = "#{title} #{invoice.invoice_number}"

  # Prawn raises on characters the built-in font cannot encode.
  def t(text)
    text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  end

  def money(amount) = Accounting::MoneyPresenter.new(amount, currency: invoice.currency).format

  def date(value) = Accounting::DatePresenter.new(value).format

  def header(pdf)
    top = pdf.cursor
    pdf.bounding_box([ 0, top ], width: 260) do
      pdf.text t([ entity.legal_name, entity.legal_form ].compact_blank.join(" ")), size: 13, style: :bold
      address_lines(entity.address_line1, entity.address_line2, [ entity.zip_code, entity.city ].compact_blank.join(" "),
                    entity.vat_number.presence && "VAT #{entity.vat_number}").each { |l| pdf.text t(l), size: 9 }
    end
    pdf.bounding_box([ 300, top ], width: pdf.bounds.width - 300) do
      pdf.text t(title), size: 20, style: :bold, align: :right
      pdf.text t(invoice.invoice_number), size: 11, align: :right
      pdf.text "Date: #{date(invoice.invoice_date)}", size: 9, align: :right
      pdf.text "Due date: #{date(invoice.due_date)}", size: 9, align: :right if invoice.due_date && !credit_note?
      if credit_note? && invoice.credited_invoice
        pdf.text t("Credits invoice #{invoice.credited_invoice.invoice_number}"), size: 9, align: :right
      end
    end
    pdf.move_down 30
  end

  def customer(pdf)
    partner = invoice.partner
    pdf.text "Bill to", size: 8, color: GREY
    pdf.text t(partner.name), size: 11, style: :bold
    address_lines(partner.street, [ partner.zip, partner.city ].compact_blank.join(" "),
                  (partner.country unless partner.country == entity.country),
                  partner.vat_number.presence && "VAT #{partner.vat_number}").each { |l| pdf.text t(l), size: 9 }
    pdf.move_down 20
  end

  def address_lines(*lines) = lines.compact_blank

  def charge_vat? = invoice.domestic?

  def lines_table(pdf)
    head = [ "Description", "Qty", "Unit price", (charge_vat? ? "VAT" : ""), "Amount excl. VAT" ]
    rows = invoice.lines.map do |l|
      [ t(l.description), l.quantity.to_s("F").sub(/\.0\z/, ""), money(l.unit_price),
        (charge_vat? ? "#{l.vat_rate.to_i}%" : ""), money(l.subtotal_excl_vat) ]
    end
    pdf.table([ head ] + rows, header: true,
              column_widths: [ 220, 40, 90, 50, 115 ], cell_style: { size: 9, borders: %i[bottom], border_color: "CCCCCC" }) do
      row(0).font_style = :bold
      columns(1..4).align = :right
    end
    pdf.move_down 12
  end

  def totals(pdf)
    rows = [ [ "Total excl. VAT", money(invoice.subtotal_excl_vat) ] ]
    if charge_vat?
      invoice.lines.group_by { |l| l.vat_rate.to_i }.sort.each do |rate, group|
        next if rate.zero?

        rows << [ "VAT #{rate}%", money(group.sum(&:vat_amount)) ]
      end
    end
    rows << [ "Total", money(invoice.total_incl_vat) ]

    pdf.table(rows, position: :right, cell_style: { size: 9, borders: [] }) do
      columns(1).align = :right
      row(-1).font_style = :bold
      row(-1).size = 11
    end
    pdf.move_down 20
  end

  def payment(pdf)
    return if credit_note? || bank.nil?

    communication = Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id))
    pdf.text "Payment", size: 10, style: :bold
    pdf.text t("IBAN: #{bank.iban}#{"   BIC: #{bank.bic}" if bank.bic.present?}"), size: 9
    pdf.text "Structured communication: #{communication}", size: 9
    pdf.move_down 15
  end

  def legal_mentions(pdf)
    mentions = [ LEGAL_MENTIONS[invoice.vat_treatment], (FRANCHISE_MENTION if entity.franchise?) ].compact
    mentions.each { |m| pdf.text t(m), size: 9, style: :italic }
  end

  def footer(pdf)
    text = "#{[ entity.legal_name, entity.vat_number ].compact_blank.join(' - ')}   Page <page> of <total>"
    pdf.number_pages t(text), at: [ 0, -10 ], width: pdf.bounds.width, align: :center, size: 8, color: GREY
  end
end

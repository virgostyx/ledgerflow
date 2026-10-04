# The PDF of a reminder (F09): the letter (sender, customer, subject, text) when `letter`, then the statement of account, the open lines of the customer
# at the day of the run with R04's balance at the end. Credits not yet allocated are shown and never deducted from what is asked for.
# Prawn like the invoice (see Accounting::InvoicePdf); its built-in font only draws Windows-1252.
# ponytail: the statement reads R05 for the whole entity once per item; pass the rows in if a run of hundreds of customers gets slow.
class Accounting::DunningPdf
  GREY = "666666".freeze

  def initialize(item, letter: true)
    @item   = item
    @letter = letter
    @entity = ActsAsTenant.current_tenant || item.entity
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: 40, info: { Title: t(@item.subject.presence || "Statement of account") })
    pdf.font "Helvetica"
    letter(pdf) if @letter
    pdf.start_new_page if @letter
    statement(pdf)
    pdf.render
  end

  private

  def t(text) = text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  def money(amount) = Accounting::MoneyPresenter.new(amount).format
  def date(value) = Accounting::DatePresenter.new(value).format

  def letter(pdf)
    pdf.text t(@entity.legal_name), size: 13, style: :bold
    [ @entity.address_line1, @entity.address_line2, [ @entity.zip_code, @entity.city ].compact_blank.join(" "), @entity.vat_number.presence && "VAT #{@entity.vat_number}" ]
      .compact_blank.each { |l| pdf.text t(l), size: 9 }
    pdf.move_down 25
    partner = @item.partner
    pdf.text t(partner.name), size: 11, style: :bold
    [ partner.street, [ partner.zip, partner.city ].compact_blank.join(" ") ].compact_blank.each { |l| pdf.text t(l), size: 9 }
    pdf.move_down 20
    pdf.text date(@item.run_on), size: 9, align: :right
    pdf.move_down 15
    pdf.text t(@item.subject), size: 12, style: :bold
    pdf.move_down 10
    pdf.text t(@item.body), size: 10
  end

  def statement(pdf)
    statement = Accounting::DunningStatement.new(partner: @item.partner, as_of: @item.run_on)
    pdf.text "Statement of account", size: 14, style: :bold
    pdf.text t("#{@item.partner.name}, #{date(@item.run_on)}"), size: 9, color: GREY
    pdf.move_down 12
    head = [ "Reference", "Due date", "Days late", "Amount", "Note" ]
    rows = statement.rows.map { |r| [ t(r.reference.presence || "-"), date(r.due_date), [ r.age_days, 0 ].max.to_s, money(r.residual), t(statement.note(r, @item)) ] }
    pdf.table([ head ] + rows, header: true, width: pdf.bounds.width, cell_style: { size: 9, borders: %i[bottom], border_color: "CCCCCC" }) do
      row(0).font_style = :bold
      columns(2..3).align = :right
    end
    pdf.move_down 12
    totals = [ [ "Balance", money(statement.balance) ], [ "Asked for", money(@item.total) ] ]
    totals += [ [ "Charges", money(@item.fees + @item.interest + @item.indemnity) ], [ "Total to pay", money(@item.grand_total) ] ] if (@item.grand_total - @item.total).positive?
    pdf.table(totals, position: :right, cell_style: { size: 9, borders: [] }) do
      columns(1).align = :right
      row(0).font_style = :bold
    end
  end
end

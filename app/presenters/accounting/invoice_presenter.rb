class Accounting::InvoicePresenter
  TYPE_LABELS = { "customer" => "Customer", "supplier" => "Supplier" }.freeze

  STATUS_LABELS = {
    "draft"     => "Draft",
    "posted"    => "Posted",
    "paid"      => "Paid",
    "cancelled" => "Cancelled"
  }.freeze

  STATUS_VARIANTS = {
    "draft"     => :default,
    "posted"    => :success,
    "paid"      => :success,
    "cancelled" => :danger
  }.freeze

  def initialize(invoice)
    @invoice = invoice
  end

  def invoice_number_or_draft
    @invoice.invoice_number.presence || "Draft"
  end

  def entry_number_display
    return @invoice.invoice_number if @invoice.invoice_number.present?

    journal = @invoice.journal
    return "—" unless journal

    year = @invoice.invoice_date&.year || Date.current.year
    "#{journal.sequence_prefix}#{year}/#{(journal.current_sequence + 1).to_s.rjust(4, '0')}"
  end

  def formatted_date
    Accounting::DatePresenter.new(@invoice.invoice_date).format
  end

  def formatted_due_date
    return "—" if @invoice.due_date.nil?

    Accounting::DatePresenter.new(@invoice.due_date).format
  end

  def formatted_total
    Accounting::MoneyPresenter.new(@invoice.total_incl_vat).format
  end

  def type_label
    TYPE_LABELS.fetch(@invoice.invoice_type.to_s, @invoice.invoice_type.to_s)
  end

  def status_label
    STATUS_LABELS.fetch(@invoice.status.to_s, @invoice.status.to_s)
  end

  def status_badge_variant
    STATUS_VARIANTS.fetch(@invoice.status.to_s, :default)
  end
end

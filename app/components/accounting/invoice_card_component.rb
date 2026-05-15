class Accounting::InvoiceCardComponent < ViewComponent::Base
  def initialize(invoice:)
    @invoice   = invoice
    @presenter = Accounting::InvoicePresenter.new(invoice)
  end

  def invoice_number = @presenter.invoice_number_or_draft
  def partner_name   = @invoice.partner.name
  def formatted_date = @presenter.formatted_date
  def formatted_total = @presenter.formatted_total
  def status_label   = @presenter.status_label
  def status_variant = @presenter.status_badge_variant
end

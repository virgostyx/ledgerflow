class Layouts::InvoiceTableComponent < ViewComponent::Base
  def initialize(invoices:)
    @invoices = invoices
  end

  def presenter_for(invoice)
    Accounting::InvoicePresenter.new(invoice)
  end
end

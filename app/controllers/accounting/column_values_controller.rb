# Lazy-loaded value checklist of a column header (see Ui::ColumnHeaderComponent).
class Accounting::ColumnValuesController < ApplicationController
  # resource => [model, :policy (Pundit scope) | :settings (admin/accountant, like Settings::BaseController)]
  RESOURCES = {
    "invoices"        => [ "Accounting::Invoice",       :policy ],
    "journal_entries" => [ "Accounting::JournalEntry",  :policy ],
    "partners"        => [ "Accounting::Partner",       :policy ],
    "payment_batches" => [ "Accounting::PaymentBatch",  :policy ],
    "vat_declarations" => [ "Accounting::VatDeclaration", :policy ],
    "fiscal_years"    => [ "Accounting::FiscalYear",    :policy ],
    "accounts"        => [ "Accounting::Account",       :settings ],
    "journals"        => [ "Accounting::Journal",       :settings ],
    "bank_accounts"   => [ "Accounting::BankAccount",   :settings ]
  }.freeze

  def show
    name, access = RESOURCES.fetch(params[:resource]) { return head :not_found }
    model = name.constantize
    return head :forbidden if access == :settings && !(current_user.admin? || current_user.accountant?)

    scope = access == :policy ? policy_scope(model) : model.all
    scope = scope.filter_by(filter_params) if model.respond_to?(:filter_by)
    scope = scope.where(invoice_type: params[:invoice_type]) if params[:invoice_type].present? && model.defined_enums.key?("invoice_type")
    @key      = params[:column]
    @selected = Array(autofilter_params[:f][@key])
    @values   = scope.autofilter_values(@key, f: autofilter_params[:f])
  end
end

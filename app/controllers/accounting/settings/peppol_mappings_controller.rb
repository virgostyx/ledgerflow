# F06 step 4: what the received invoices are turned into: how each UBL VAT category is treated (an unmapped one makes a message wait for the
# accountant), and the expense account proposed for each supplier. Editable data, audited.
class Accounting::Settings::PeppolMappingsController < Accounting::Settings::BaseController
  before_action { authorize Accounting::PeppolMessage, :configure?, policy_class: Accounting::PeppolMessagePolicy }

  def edit
    Accounting::VatCategoryMapping.ensure_defaults!
    load
  end

  def update
    ApplicationRecord.transaction do
      save_mappings
      save_defaults
    end
    redirect_to edit_accounting_settings_peppol_mappings_path, notice: "Saved"
  rescue ActiveRecord::RecordInvalid => e
    load
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_content
  end

  private

  def load
    @mappings = Accounting::VatCategoryMapping.all.index_by(&:category)
    @defaults = Accounting::SupplierDefault.includes(:partner, :account).order(:id)
    @accounts = Accounting::Account.where(is_leaf: true).order(:code)
  end

  # A blank treatment unmaps the category: a document that carries it then waits for the accountant.
  def save_mappings
    params.fetch(:mappings, {}).each do |category, attrs|
      next unless Accounting::VatCategoryMapping::CATEGORIES.include?(category)

      mapping = Accounting::VatCategoryMapping.find_by(category: category)
      if attrs[:vat_treatment].blank?
        mapping&.destroy!
      else
        (mapping || Accounting::VatCategoryMapping.new(category: category)).update!(vat_treatment: attrs[:vat_treatment], vat_rate: attrs[:vat_rate].presence)
      end
    end
  end

  def save_defaults
    params.fetch(:defaults, {}).each do |id, attrs|
      Accounting::SupplierDefault.find(id).update!(account_id: attrs[:account_id].presence)
    end
  end
end

module Accounting::FiscalYearScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :fiscal_year, class_name: "Accounting::FiscalYear"
    scope :for_fiscal_year, ->(fy) { where(fiscal_year: fy) }
  end
end

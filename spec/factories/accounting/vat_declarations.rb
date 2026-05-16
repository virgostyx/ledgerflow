FactoryBot.define do
  factory :vat_declaration, class: 'Accounting::VatDeclaration' do
    association :fiscal_year, factory: :fiscal_year

    period_type  { :quarterly }
    period_start { Date.new(2025, 1, 1) }
    period_end   { Date.new(2025, 3, 31) }
    status       { :draft }
    grids        { {} }
  end
end

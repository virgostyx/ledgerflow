FactoryBot.define do
  factory :invoice_line_annotation, class: "Accounting::InvoiceLineAnnotation" do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    association :analytical_axis
    association :invoice_line

    analytical_account do
      create(:analytical_account, analytical_axis: analytical_axis)
    end
  end
end

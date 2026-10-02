FactoryBot.define do
  factory :document, class: "Accounting::Document" do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    sequence(:name) { |n| "document-#{n}.pdf" }
    content_type { "application/pdf" }
    origin { :manual_upload }
    kind { :other }
    status { :inbox }
    association :uploaded_by, factory: :user

    transient { content { nil } }

    after(:build) do |document, evaluator|
      bytes = evaluator.content || Prawn::Document.new { |pdf| pdf.text document.name }.render
      document.sha256 = Digest::SHA256.hexdigest(bytes)
      document.byte_size = bytes.bytesize
      document.file.attach(io: StringIO.new(bytes), filename: document.name, content_type: document.content_type)
    end
  end
end

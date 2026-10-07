# Knowledge documents for the specs (A06): added through the real ingestion, then reviewed unless said otherwise. The texts are invented for the specs; nothing here is a statement of Belgian law.
module KnowledgeHelpers
  def add_knowledge(text, entity: ActsAsTenant.current_tenant, reviewed: true, scope: "company", organization: nil, **attributes)
    author = attributes.delete(:author) || create(:user)
    result = Knowledge::Ingest.call(attributes: { title: "Note", source: "Internal", licence: "Own work", valid_from: Date.new(2020, 1, 1), language: "en" }.merge(attributes), user: author, entity: entity, text: text,
                                    new_version_of: attributes.delete(:new_version_of))
    raise "ingest failed: #{result.reason} #{result.errors}" unless result.success?

    document = result.document
    document.update_columns(scope: scope, entity_id: (scope == "company" ? entity.id : nil), organization_id: organization&.id)
    document.update_columns(status: "reviewed", reviewed_at: Time.current, reviewed_by_id: create(:user).id) if reviewed
    document
  end
end

RSpec.configure { |config| config.include KnowledgeHelpers }

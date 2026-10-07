# A06: the curated, dated knowledge base the agent answers methodological questions from. A document belongs to the platform (read-only for everyone), to an organization (its
# entities) or to one entity. A document is only used once a person other than its author has reviewed it (when four-eyes is on). Chunks carry the full text index (unaccent, one
# text search configuration per language). `knowledge_gaps` is what the base could not answer. Reversible.
class CreateKnowledgeBase < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_documents do |t|
      t.string :scope, null: false, default: "company"            # platform | organization | company
      t.references :entity, foreign_key: true                       # company scope only
      t.references :organization, foreign_key: true                 # organization scope only
      t.string  :title, null: false
      t.string  :source, null: false
      t.string  :licence, null: false
      t.string  :source_type, null: false, default: "note"          # pcmn | procedure | sheet | note
      t.string  :jurisdiction, null: false, default: "BE"
      t.string  :language, null: false, default: "fr"
      t.date    :valid_from, null: false
      t.date    :valid_to
      t.string  :series, null: false                                # versions of one document share a series
      t.integer :version, null: false, default: 1
      t.string  :status, null: false, default: "draft"              # draft | reviewed | retired
      t.text    :body, null: false
      t.string  :content_sha256, null: false
      t.boolean :injection_suspected, null: false, default: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.datetime :retired_at
      t.timestamps
    end
    add_index :knowledge_documents, %i[series version], unique: true
    add_index :knowledge_documents, %i[status scope]

    create_table :knowledge_chunks do |t|
      t.references :document, null: false, foreign_key: { to_table: :knowledge_documents, on_delete: :cascade }
      t.integer :position, null: false
      t.string  :section
      t.text    :content, null: false
      t.string  :quality, null: false, default: "normal"             # normal | low (a table, a footnote, almost no words)
      t.string  :config, null: false, default: "french"              # french | dutch | english
      t.column  :search_vector, :tsvector
      t.timestamps
    end
    add_index :knowledge_chunks, %i[document_id position], unique: true
    add_index :knowledge_chunks, :search_vector, using: :gin

    create_table :knowledge_gaps do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :message, foreign_key: { to_table: :agent_messages, on_delete: :nullify }
      t.string :kind, null: false                                    # no_passage | not_useful
      t.text   :question, null: false                                # encrypted
      t.string :question_key, null: false                            # digest of the normalised question, to count the same one asked again
      t.timestamps
    end
    add_index :knowledge_gaps, %i[entity_id kind question_key]
  end
end

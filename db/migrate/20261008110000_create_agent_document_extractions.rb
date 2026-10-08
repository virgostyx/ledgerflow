# A09: the model reads a document the local extraction of F03 does not handle, and what it read is kept here as a proposal (encrypted: it holds the business data of the document), with where each field
# was found and what the server checked. Nothing goes into the document's data until a person confirms. `agent_settings.document_mode` says what may leave: `text_only` (the masked text; the only mode
# that exists) or, once the owners and the product agree, `full_document`. Reversible.
class CreateAgentDocumentExtractions < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_settings, :document_mode, :string, null: false, default: "text_only"

    create_table :agent_document_extractions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: { to_table: :accounting_documents, on_delete: :cascade }
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.string   :engine, null: false                                   # ubl | agent_text
      t.string   :status, null: false, default: "proposed"              # proposed | confirmed | rejected | failed
      t.string   :document_type                                         # invoice | credit_note | quote | proforma | purchase_order | contract | letter | other
      t.text     :payload                                               # encrypted: { fields:, validation:, warnings: }
      t.string   :coverage, null: false, default: "full"                # full | partial (more pages than were read)
      t.boolean  :suspicious, null: false, default: false               # the text looked like an instruction to an AI
      t.string   :model
      t.integer  :input_tokens, null: false, default: 0
      t.integer  :output_tokens, null: false, default: 0
      t.string   :error
      t.string   :batch_key                                             # the documents of one batch share it
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :agent_document_extractions, %i[entity_id status]
    add_index :agent_document_extractions, %i[document_id created_at]
  end
end

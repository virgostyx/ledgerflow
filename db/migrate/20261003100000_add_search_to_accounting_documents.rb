# F03 search: one lower-case, accent-free text per document (its name, the text read from it and the values read from it),
# kept up to date by PostgreSQL itself (a generated column) and searched by substring through a trigram index. That
# finds an invoice number, an amount or a word typed with or without accents, in any language.
# unaccent() is not IMMUTABLE, which a generated column or an index needs: the usual wrapper f_unaccent() is.
class AddSearchToAccountingDocuments < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION f_unaccent(text) RETURNS text AS $$
        SELECT public.unaccent('public.unaccent', $1)
      $$ LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;

      ALTER TABLE accounting_documents ADD COLUMN search_blob text GENERATED ALWAYS AS (
        lower(f_unaccent(
          coalesce(name, '') || ' ' || coalesce(search_text, '') || ' ' ||
          coalesce(jsonb_path_query_array(extracted_data, '$.extraction.fields.*.value')::text, '')
        ))
      ) STORED;

      CREATE INDEX idx_documents_search_blob ON accounting_documents USING gin (search_blob gin_trgm_ops);
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX idx_documents_search_blob;
      ALTER TABLE accounting_documents DROP COLUMN search_blob;
      DROP FUNCTION f_unaccent(text);
    SQL
  end
end

# Full text search of the knowledge base (A06), in PostgreSQL: accents do not matter, each passage is read in the language of its document, and the words of the question are alternatives (the more
# of them a passage holds, the higher it ranks). Only what the entity may see, reviewed, and in force on the day asked is searched; a passage of low quality comes after the others. Vector search is not
# used: the evaluation set (A06 cases) says whether the full text is enough.
class Knowledge::Search
  MAX_WORDS = 12
  Hit = Data.define(:chunk, :document, :rank, :words)

  def self.call(entity:, query:, as_of: Date.current, top_k: 6, jurisdiction: nil, source_types: nil)
    words = words_of(query)
    return [] if words.empty?

    documents = Knowledge::Document.usable_by(entity, on: as_of)
    documents = documents.where(jurisdiction: jurisdiction) if jurisdiction.present?
    documents = documents.where(source_type: source_types) if source_types.present?
    tsquery = Knowledge::Chunk.sanitize_sql_array([ "to_tsquery(knowledge_chunks.config::regconfig, f_unaccent(?))", words.join(" | ") ])
    chunks = Knowledge::Chunk.joins(:document).merge(documents).includes(:document).where("knowledge_chunks.search_vector @@ #{tsquery}").where(matching_words(words))
               .select("knowledge_chunks.*, ts_rank_cd(knowledge_chunks.search_vector, #{tsquery}) AS rank")
               .order(Arel.sql("CASE knowledge_chunks.quality WHEN 'low' THEN 1 ELSE 0 END"), Arel.sql("rank DESC"), :id).limit(top_k)
    chunks.map { |chunk| Hit.new(chunk: chunk, document: chunk.document, rank: chunk[:rank].to_f, words: words) }
  end

  # A passage that holds only one word of a question of three or more is a coincidence ("advance" in "a grant received in advance"), not an answer: it needs two. The count is made in SQL, word by word, in the language of the passage.
  def self.matching_words(words)
    needed = words.size >= 3 ? 2 : 1
    counts = words.map { |word| Knowledge::Chunk.sanitize_sql_array([ "(knowledge_chunks.search_vector @@ to_tsquery(knowledge_chunks.config::regconfig, f_unaccent(?)))::int", word ]) }
    "#{counts.join(' + ')} >= #{needed}"
  end
  private_class_method :matching_words

  # The words worth searching: letters and digits only (nothing of the query reaches the search syntax), three characters or more, no repeat.
  def self.words_of(query) = query.to_s.downcase.scan(/[\p{L}\p{N}]{3,}/).uniq.first(MAX_WORDS)
end

# B03c: writes the fingerprint of a validated entry. At the validation it is `live`, in the transaction of the validation; for what was validated before the fingerprints existed
# (or before its lines were), it is written afterwards and says so: `retroactive`. Once written it never changes (the database refuses).
#
# => true when it wrote one, false when there was nothing to write (it has one, it is a draft, or it has no line yet)
module Ledger::Seal
  SOURCES = %w[live retroactive].freeze

  def self.call(entry, source:)
    raise ArgumentError, "source: #{SOURCES.join(' or ')}" unless SOURCES.include?(source)

    fresh = Accounting::JournalEntry.find(entry.id) # the instant and the place are given by the database: not what the object in memory believes
    return false if fresh.content_hash || fresh.posted_seq.nil? || !Accounting::JournalEntryLine.exists?(journal_entry_id: fresh.id)

    written = with_period_lock_lifted do
      Accounting::JournalEntry.where(id: fresh.id, content_hash: nil).update_all(content_hash: Ledger::EntryContent.digest(fresh), content_hash_source: source)
    end
    written.positive?
  end

  # A validated entry in a locked period may still get its fingerprint (nothing else of it changes): the lifting lasts the statement.
  def self.with_period_lock_lifted
    connection = ApplicationRecord.connection
    before = connection.select_value("SELECT current_setting('ledgerflow.lock_override', true)")
    connection.execute("SELECT set_config('ledgerflow.lock_override', 'on', true)")
    yield
  ensure
    connection.execute("SELECT set_config('ledgerflow.lock_override', #{connection.quote(before.to_s)}, true)")
  end
  private_class_method :with_period_lock_lifted

  # The same for many entries at once (the retroactive anchor of a company that has hundreds of thousands): their lines read in one query, their fingerprints written in one
  # statement. Entries that are not validated, or have no line, get nothing. => the ids that got one
  def self.many(entries, source:)
    raise ArgumentError, "source: #{SOURCES.join(' or ')}" unless SOURCES.include?(source)

    todo = Accounting::JournalEntry.where(id: entries.map(&:id), content_hash: nil).where.not(posted_seq: nil).order(:posted_seq).to_a
    return [] if todo.empty?

    rows = Ledger::EntryContent.canonical_many(todo).reject { |_, content| content["lines"].empty? }.map { |entry, content| [ entry.id, Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(content)) ] }
    return [] if rows.empty?

    connection = ApplicationRecord.connection
    values = rows.map { |id, hash| "(#{id.to_i}, #{connection.quote(hash)})" }.join(", ")
    with_period_lock_lifted do
      connection.execute("UPDATE accounting_journal_entries e SET content_hash = v.h, content_hash_source = #{connection.quote(source)} FROM (VALUES #{values}) AS v(id, h) WHERE e.id = v.id AND e.content_hash IS NULL")
    end
    rows.map(&:first)
  end
end

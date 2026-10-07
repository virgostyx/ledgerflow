# The state of an entity's books, as a short fingerprint (A05): the number of validated entries and the last time one changed. An answer keeps the one it was computed from, so that "Check" can say whether
# the books have moved since, even when the figures asked about have not.
module Agent::LedgerVersion
  def self.current
    entries = Accounting::JournalEntry.where(status: Accounting::JournalEntry.ledger_status_values)
    Digest::SHA256.hexdigest([ entries.count, entries.maximum(:updated_at)&.utc&.iso8601(6) ].join("|"))[0, 16]
  end
end

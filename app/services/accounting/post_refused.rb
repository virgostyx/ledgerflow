# Raised by PostJournalEntry.call! when an entry cannot be validated (locked period, unbalanced...).
class Accounting::PostRefused < StandardError; end

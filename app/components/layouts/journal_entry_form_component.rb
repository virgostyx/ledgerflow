class Layouts::JournalEntryFormComponent < ViewComponent::Base
  def initialize(entry:, journals:, accounts:)
    @entry    = entry
    @journals = journals
    @accounts = accounts
  end

  def accounts_json
    @accounts.map { |a| { id: a.id, code: a.code, label: a.label_fr } }.to_json
  end

  def form_url
    @entry.persisted? ? accounting_journal_entry_path(@entry) : accounting_journal_entries_path
  end
end

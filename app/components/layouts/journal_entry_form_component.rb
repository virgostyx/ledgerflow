class Layouts::JournalEntryFormComponent < ViewComponent::Base
  def initialize(entry:, journals:, accounts:, axes: [])
    @entry    = entry
    @journals = journals
    @accounts = accounts
    @axes     = axes
  end

  def accounts_json
    @accounts.map { |a| { id: a.id, code: a.code, label: a.label_fr, account_class: a.account_class } }.to_json
  end

  def axes_json
    @axes.map do |axis|
      {
        id:           axis.id,
        code:         axis.code,
        label:        axis.label_fr,
        required_for: axis.required_for_account_classes,
        accounts:     axis.analytical_accounts.active.ordered.map do |aa|
          { id: aa.id, code: aa.code, label: aa.label_fr }
        end
      }
    end.to_json
  end

  def form_url
    @entry.persisted? ? accounting_journal_entry_path(@entry) : accounting_journal_entries_path
  end

  def axes
    @axes
  end
end

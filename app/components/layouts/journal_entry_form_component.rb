class Layouts::JournalEntryFormComponent < ViewComponent::Base
  # posting: whether saving a new entry posts it at once (the person may post, and it is not an agent proposal). The label says what
  # will happen: a posted entry is permanent, a draft can still be edited.
  def initialize(entry:, journals:, accounts:, axes: [], agent_proposal: nil, posting: false)
    @posting = posting
    @agent_proposal = agent_proposal
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

  def field_class = Layouts::JournalEntryLineComponent::FIELD

  def header_label_class = "mb-0.5 block text-xs text-gray-600"

  def submit_label = @posting ? "Post entry" : "Save as draft"

  def save_consequence
    if @posting
      "Posting records the entry permanently; it can only be reversed. If another person must validate it, it is saved as a draft instead."
    else
      "A draft can be edited until it is validated."
    end
  end

  def discard_label = @entry.persisted? ? "Discard these changes?" : "Discard this entry?"

  def form_url
    @entry.persisted? ? accounting_journal_entry_path(@entry) : accounting_journal_entries_path
  end

  def axes
    @axes
  end

  # EUR first, then the other currencies of the application.
  def currency_options = [ "EUR" ] + (Accounting::MoneyPresenter::SUPPORTED_CURRENCIES - [ "EUR" ])

  def partners
    @partners ||= Accounting::Partner.where(active: true).order(:name)
  end
end

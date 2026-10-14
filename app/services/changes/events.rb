# B03b R21: the changes that are not entries - lettering, setup (master data), locks, documents, payments, IBAN - between two instants, in order. Every one comes from a
# table that only grows (the lettering events, the versions of master data, the audit trail), so a change cannot be missing because the thing was edited since.
class Changes::Events
  Event = Struct.new(:category, :at, :action, :actor_id, :reason, :subject_type, :subject_id, :detail, keyword_init: true)

  # The audit actions that are changes, by category. What is not listed (a login, a read, a download) is not a change of the books.
  AUDIT_CATEGORIES = {
    locks: %w[lock_period unlock_period relock_period closing_locked closing_reopened controlled_window_opened controlled_window_closed controlled_window_used],
    documents: %w[document_upload document_archive document_link document_unlink document_delete document_split document_duplicate_override document_legal_hold],
    payments: %w[payment_batch_composed payment_batch_submitted payment_batch_exported payment_batch_cancelled payment_batch_cancel_requested payment_batch_debit_linked
                 payment_batch_entries_posted payment_rejected payment_returned payment_batch_double_payment_suspected],
    iban: %w[bank_account_registered bank_account_changed bank_account_superseded bank_account_verified bank_account_blocked bank_account_distrusted]
  }.freeze
  CATEGORIES = (%i[lettering setup] + AUDIT_CATEGORIES.keys).freeze

  def self.call(**args) = new(**args).call

  def initialize(from:, to: nil, categories: nil)
    @from = from
    @to = to
    @categories = categories ? Array(categories).map(&:to_sym) & CATEGORIES : CATEGORIES
  end

  def call = (lettering + setup + audited).sort_by { |e| [ e.at, e.category.to_s ] }

  private

  # After T1 and up to T2 (an instant is known at itself): the same bounds as the entries.
  def within(scope, column)
    scope = scope.where(scope.arel_table[column].gt(@from))
    @to ? scope.where(scope.arel_table[column].lteq(@to)) : scope
  end

  def lettering
    return [] unless @categories.include?(:lettering)

    within(Accounting::LetteringEvent.all, :created_at).order(:created_at, :id).map do |e|
      Event.new(category: :lettering, at: e.created_at, action: e.action, actor_id: e.user_id, reason: e.reason, subject_type: "Accounting::JournalEntryLine", subject_id: e.line_id,
                detail: { "code" => e.code, "auto" => e.auto, "lettered_on" => e.lettered_on })
    end
  end

  def setup
    return [] unless @categories.include?(:setup)

    within(Accounting::MasterDataVersion.all, :valid_from).order(:valid_from, :id).map do |v|
      Event.new(category: :setup, at: v.valid_from, action: "master_data_version", actor_id: nil, reason: nil, subject_type: v.record_type, subject_id: v.record_id, detail: v.attrs)
    end
  end

  def audited
    actions = AUDIT_CATEGORIES.slice(*@categories).values.flatten
    return [] if actions.empty?

    category = AUDIT_CATEGORIES.each_with_object({}) { |(cat, list), h| list.each { |a| h[a] = cat } }
    within(Accounting::AuditLog.where(action: actions), :created_at).order(:created_at, :id).map do |l|
      Event.new(category: category.fetch(l.action), at: l.created_at, action: l.action, actor_id: l.user_id, reason: l.reason, subject_type: l.auditable_type, subject_id: l.auditable_id, detail: l.payload)
    end
  end
end

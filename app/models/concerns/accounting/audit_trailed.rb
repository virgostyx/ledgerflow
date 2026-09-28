# Writes one entry in the append-only, hash-chained audit trail (R18) per create, update and destroy of a
# record, with the field-by-field before/after in `payload["changes"]` (distinct from Accounting::Auditable,
# which keeps the PaperTrail versions). A model may define `skip_audit?` for changes that a dedicated service
# already logs under its own action (posting, reversal).
module Accounting::AuditTrailed
  extend ActiveSupport::Concern

  IGNORED_FIELDS = %w[updated_at created_at].freeze

  included do
    after_create  { audit_change("create", saved_changes.transform_values { |(_, after)| [ nil, after ] }) }
    after_update  { audit_change("update", saved_changes) }
    after_destroy { audit_change("destroy", attributes.transform_values { |value| [ value, nil ] }) }
  end

  private

  def audit_change(action, changes)
    return if action == "update" && skip_audit?

    fields = changes.except(*IGNORED_FIELDS).transform_values { |pair| pair.as_json }
    return if fields.empty?

    Accounting::AuditLog.record!(auditable: self, action: action, payload: { changes: fields })
  end

  def skip_audit? = false
end

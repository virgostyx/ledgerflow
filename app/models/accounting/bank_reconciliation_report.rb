# A frozen bank reconciliation (R06, docs/dev/reports/spec.md §8): the full
# result as of a date, hashed for tamper detection, immutable once created
# (see the DB trigger in its migration — same pattern as Accounting::AuditLog).
class Accounting::BankReconciliationReport < ApplicationRecord
  self.table_name = "accounting_bank_reconciliation_reports"

  belongs_to :bank_account, class_name: "Accounting::BankAccount"
  belongs_to :user, optional: true

  validates :as_of, presence: true
  validates :result, presence: true

  def self.record!(bank_account:, as_of:, result:, user: nil)
    create!(
      bank_account: bank_account,
      as_of:        as_of,
      result:       result,
      content_hash: Digest::SHA256.hexdigest(result.to_json),
      user_id:      user&.id,
      entity_id:    ActsAsTenant.current_tenant&.id
    )
  end
end

class Accounting::AuditLog < ApplicationRecord
  self.table_name = "accounting_audit_logs"

  belongs_to :user, optional: true

  validates :auditable_type, presence: true
  validates :auditable_id,   presence: true
  validates :action,         presence: true

  scope :for_record,  ->(record)  { where(auditable_type: record.class.name, auditable_id: record.id) }
  scope :for_action,  ->(action)  { where(action: action) }
  scope :chronologic, -> { order(created_at: :asc) }

  def self.record!(auditable:, action:, user: nil, payload: {}, ip_address: nil)
    create!(
      auditable_type: auditable.class.name,
      auditable_id:   auditable.id,
      action:         action,
      user_id:        user&.id,
      user_email:     user&.email,
      payload:        payload,
      ip_address:     ip_address
    )
  end
end

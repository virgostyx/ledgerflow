# A group of journal lines on one account that cancel each other out (total debit == total credit).
# The balance rule is enforced by Accounting::LetterLines, not here, so partial lettering stays possible later.
class Accounting::Lettering < ApplicationRecord
  self.table_name = "accounting_letterings"

  acts_as_tenant :entity

  belongs_to :account, class_name: "Accounting::Account"
  belongs_to :partner, class_name: "Accounting::Partner", optional: true
  has_many   :lines, class_name: "Accounting::JournalEntryLine",
             foreign_key: :lettering_id, inverse_of: :lettering, dependent: :nullify

  validates :code,        presence: true, uniqueness: { scope: %i[entity_id account_id] }
  validates :lettered_on, presence: true

  # AA, AB, ... AZ, BA, ... (per account)
  def self.next_code_for(account)
    last = where(account: account).order(:code).last&.code
    last ? last.succ : "AA"
  end
end

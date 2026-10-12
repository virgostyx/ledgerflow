# A bank account a supplier is paid on (B01b). New or changed, it starts unverified and is observed for a few hours; another person verifies it, after
# calling the supplier on a number known beforehand. Only a verified account whose observation is over can be used in a payment batch. The IBAN is
# encrypted at rest and never written in full in a journal (see #masked_iban). Nothing a document says (Peppol, an import, the assistant) makes or changes
# one: a person registers it.
class Accounting::PartnerBankAccount < ApplicationRecord
  self.table_name = "partner_bank_accounts"

  acts_as_tenant :entity

  encrypts :iban, deterministic: true

  enum :status, { unverified: 0, verified: 1, blocked: 2, superseded: 3 }
  enum :source, { manual: 0, invoice: 1, import: 2 }
  enum :verification_method, { phone_callback: 0, signed_letter: 1, supplier_statement: 2, other: 3 }, prefix: :via

  belongs_to :partner, class_name: "Accounting::Partner"
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", optional: true
  belongs_to :previous_account, class_name: "Accounting::PartnerBankAccount", optional: true

  before_validation { self.iban = Accounting::Iban.normalize(iban) }

  validates :holder_name, presence: true
  validates :first_seen_at, :cooling_until, presence: true
  validate  :iban_is_valid
  validate  :iban_not_already_live

  scope :live, -> { where(status: %i[unverified verified blocked]) }

  # The account a payment to this supplier goes to: the newest that is verified and no longer observed, or none.
  def self.usable_for(partner) = where(partner: partner, status: :verified).where(cooling_until: ..Time.current).order(:verified_at).last

  # Verified and no longer observed: the only state in which a payment may go to it.
  def usable? = verified? && cooling_until <= Time.current

  # BE68 **** **** 7034: what a screen or a journal may say of it.
  def masked_iban
    number = iban.to_s
    return number if number.length <= 8

    masked = number[0, 4] + ("*" * (number.length - 8)) + number[-4..]
    masked.scan(/.{1,4}/).join(" ")
  end

  private

  def iban_is_valid
    errors.add(:iban, :invalid) unless Accounting::Iban.valid?(iban) && Accounting::Iban::LENGTHS.key?(iban.to_s[0, 2])
  end

  # The same account twice for one supplier is a mistake; one that was replaced may come back (as a new account, observed again).
  def iban_not_already_live
    return if iban.blank? || superseded?

    errors.add(:iban, :taken) if self.class.live.where(partner_id: partner_id, iban: iban).where.not(id: id).exists?
  end
end

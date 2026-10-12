# How a bank takes its payment file (B01b): the version of the format and the options come from the documentation of the bank or from the bank itself, never
# from a guess; `format_verified` says that a file of this version was seen to be taken, `coda_verified` that a CODA of this bank was seen, so that a batch can be
# recognised on its statement.
class Payments::BankProfile < ApplicationRecord
  self.table_name = "payment_bank_profiles"

  acts_as_tenant :entity

  validates :name, :format_version, :encoding, presence: true
end

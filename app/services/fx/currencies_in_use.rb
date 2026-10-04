# The foreign currencies an entity actually works in (F11): those of its invoices, partners, accounts and ledger lines. EUR is never one of them.
module Fx::CurrenciesInUse
  def self.call
    [ Accounting::Invoice.distinct.pluck(:currency), Accounting::Partner.distinct.pluck(:currency), Accounting::Account.where.not(currency: nil).distinct.pluck(:currency),
      Accounting::JournalEntryLine.distinct.pluck(:currency) ].flatten.uniq.compact.reject { |c| c == "EUR" }.sort
  end
end

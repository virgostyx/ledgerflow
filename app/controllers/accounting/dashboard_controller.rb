class Accounting::DashboardController < ApplicationController
  def index
    draft_invoices       = Accounting::Invoice.draft.count
    draft_entries        = Accounting::JournalEntry.draft.count
    treasury_balance     = Accounting::BankTransaction.sum(:amount)

    @kpis = [
      { label: "Invoices to validate", value: draft_invoices,                                  icon: "document-text" },
      { label: "Treasury balance",     value: helpers.number_to_currency(treasury_balance, unit: "€"), icon: "banknotes" },
      { label: "Draft entries",        value: draft_entries,                                   icon: "book-open" }
    ]
  end
end

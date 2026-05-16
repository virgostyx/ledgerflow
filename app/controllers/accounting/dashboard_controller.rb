class Accounting::DashboardController < ApplicationController
  def index
    draft_invoices   = Accounting::Invoice.draft.count
    draft_entries    = Accounting::JournalEntry.draft.count
    treasury_balance = Accounting::BankTransaction.sum(:amount)

    @kpis = [
      {
        title: "Invoices to validate",
        value: draft_invoices,
        icon:  :document_text,
        color: draft_invoices.positive? ? :amber : :primary
      },
      {
        title: "Treasury balance",
        value: helpers.number_to_currency(treasury_balance, unit: "€"),
        icon:  :banknotes,
        color: treasury_balance.negative? ? :red : :green
      },
      {
        title: "Draft entries",
        value: draft_entries,
        icon:  :book_open,
        color: draft_entries.positive? ? :amber : :primary
      }
    ]
  end
end

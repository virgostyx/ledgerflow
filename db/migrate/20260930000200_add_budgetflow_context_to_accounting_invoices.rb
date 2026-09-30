# What BudgetFlow sends with an invoice so the accountant can choose the analytical accounts in LedgerFlow: the
# project name and the budget line (chapter.line.sub_line).
class AddBudgetflowContextToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :external_project_name, :string
    add_column :accounting_invoices, :external_budget_line, :string
  end
end

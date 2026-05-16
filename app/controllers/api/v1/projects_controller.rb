class Api::V1::ProjectsController < Api::V1::BaseController
  def accounting_summary
    project_id = params[:id].to_i
    lines = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(accounting_journal_entries: { project_id: project_id, status: :posted })

    charges = lines.joins(:account)
                   .where(accounting_accounts: { account_type: :expense })
                   .sum(:debit)

    produits = lines.joins(:account)
                    .where(accounting_accounts: { account_type: :revenue })
                    .sum(:credit)

    solde = charges - produits

    render json: {
      project_id:       project_id,
      charges:          charges.to_s,
      produits:         produits.to_s,
      solde:            solde.to_s,
      taux_absorption:  0
    }
  end
end

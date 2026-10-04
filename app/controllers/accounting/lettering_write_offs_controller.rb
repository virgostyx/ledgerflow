# F04: closes a lettering that misses balancing by a rounding difference with a draft entry (the lines are lettered when it is validated).
class Accounting::LetteringWriteOffsController < ApplicationController
  def create
    authorize Accounting::Lettering, :create?
    lines  = Accounting::JournalEntryLine.where(id: Array(params[:line_ids])).to_a
    result = Accounting::WriteOffLettering.call(lines: lines, user: current_user)

    if result.success?
      redirect_to accounting_journal_entry_path(result[:entry]), notice: "Rounding entry created as a draft: validate it to letter the lines"
    else
      redirect_to new_accounting_lettering_path(account_id: params[:account_id]), alert: result.message
    end
  end
end

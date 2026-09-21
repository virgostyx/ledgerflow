class Accounting::LineAllocationsController < ApplicationController
  def create
    authorize Accounting::LineAllocation
    lines  = Accounting::JournalEntryLine.where(id: Array(params[:line_ids])).includes(:journal_entry, :account, :invoice).to_a
    result = Accounting::AllocateLines.call(lines: lines)

    back(result.success? ? { notice: notice_for(result) } : { alert: result.message }, params[:account_id])
  end

  def destroy
    allocation = Accounting::LineAllocation.find(params[:id])
    authorize allocation
    result = Accounting::RemoveAllocation.call(allocation: allocation)

    back(result.success? ? { notice: "Allocation removed" } : { alert: result.message }, allocation.debit_line.account_id)
  end

  private

  def notice_for(result)
    result.lettering ? "Settled and lettered (#{result.lettering.code})" : "Payment allocated"
  end

  def back(flash_options, account_id)
    redirect_to new_accounting_lettering_path(account_id: account_id), flash_options
  end
end

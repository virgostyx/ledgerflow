class Accounting::LetteringsController < ApplicationController
  def new
    authorize Accounting::Lettering
    load_lines
  end

  def create
    authorize Accounting::Lettering
    lines  = Accounting::JournalEntryLine.where(id: Array(params[:line_ids])).includes(:journal_entry, :account).to_a
    result = Accounting::LetterLines.call(lines: lines)

    if result.success?
      redirect_to new_accounting_lettering_path(account_id: result.lettering.account_id),
                  notice: "Lines lettered (#{result.lettering.code})"
    else
      load_lines
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    lettering = Accounting::Lettering.find(params[:id])
    authorize lettering
    result = Accounting::UnletterLines.call(lettering: lettering)

    redirect_to new_accounting_lettering_path(account_id: lettering.account_id),
                result.success? ? { notice: "Lettering #{lettering.code} removed" } : { alert: result.message }
  end

  private

  def load_lines
    @accounts = Accounting::Account.where(is_leaf: true).or(Accounting::Account.where(reconcilable: true)).order(:code)
    @account  = @accounts.find_by(id: params[:account_id])
    return unless @account

    @lines = Accounting::JournalEntryLine.where(account: @account, lettering_id: nil)
               .joins(:journal_entry).merge(Accounting::JournalEntry.posted)
               .includes(:partner, :journal_entry).order(:partner_id, "accounting_journal_entries.entry_date", :id)
    @letterings = Accounting::Lettering.where(account: @account).includes(:partner).order(code: :desc).limit(20)
    @allocations = Accounting::LineAllocation.where(debit_line_id: @lines.map(&:id)).includes(debit_line: :journal_entry, credit_line: %i[journal_entry partner])
  end
end

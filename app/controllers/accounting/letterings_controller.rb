class Accounting::LetteringsController < ApplicationController
  def new
    authorize Accounting::Lettering
    load_lines
  end

  def create
    authorize Accounting::Lettering
    lines  = Accounting::JournalEntryLine.where(id: Array(params[:line_ids])).includes(:journal_entry, :account).to_a
    result = Accounting::LetterLines.call(lines: lines, user: current_user, reason: params[:reason], cross_partner: params[:cross_partner] == "1")

    if result.success?
      redirect_to new_accounting_lettering_path(account_id: result.lettering.account_id),
                  notice: "Lines lettered (#{result.lettering.code})"
    else
      load_lines
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  # The history of a lettering: its lines, and every lettering and unlettering those lines went through.
  def show
    @lettering = Accounting::Lettering.find(params[:id])
    authorize @lettering
    @lines  = @lettering.lines.includes(:journal_entry, :partner).order(:id)
    @events = Accounting::LetteringEvent.where(line_id: @lines.map(&:id)).includes(:user).order(:id)
  end

  def destroy
    lettering = Accounting::Lettering.find(params[:id])
    authorize lettering
    result = Accounting::UnletterLines.call(lettering: lettering, user: current_user, reason: params[:reason])

    redirect_to new_accounting_lettering_path(account_id: lettering.account_id),
                result.success? ? { notice: "Lettering #{lettering.code} removed" } : { alert: result.message }
  end

  private

  # Age (days since the entry date), amount (debit + credit) and state (open, or partly settled by allocations).
  def filter(scope)
    amount = "(accounting_journal_entry_lines.debit + accounting_journal_entry_lines.credit)"
    scope = scope.where(partner_id: params[:partner_id]) if params[:partner_id].present?
    scope = scope.where("#{amount} >= ?", BigDecimal(params[:min_amount])) if params[:min_amount].present?
    scope = scope.where("#{amount} <= ?", BigDecimal(params[:max_amount])) if params[:max_amount].present?
    scope = scope.where("accounting_journal_entries.entry_date <= ?", Date.current - params[:older_than].to_i) if params[:older_than].present?
    case params[:state]
    when "open"   then scope.where("#{amount} = accounting_journal_entry_lines.amount_residual")
    when "partly" then scope.where("#{amount} <> accounting_journal_entry_lines.amount_residual")
    else scope
    end
  rescue ArgumentError
    scope
  end

  def load_lines
    @accounts = Accounting::Account.where(is_leaf: true).or(Accounting::Account.where(reconcilable: true)).order(:code)
    @account  = @accounts.find_by(id: params[:account_id])
    return unless @account

    open_lines = Accounting::JournalEntryLine.where(account: @account, lettering_id: nil).joins(:journal_entry).merge(Accounting::JournalEntry.posted)
    @partners = Accounting::Partner.where(id: open_lines.select(:partner_id)).order(:name)
    @lines = filter(open_lines)
               .includes(:partner, :journal_entry).order(:partner_id, "accounting_journal_entries.entry_date", :id)
    @suggestions = Accounting::LetteringSuggestion.proposed.where(account: @account).includes(:partner).order(score: :desc, id: :asc)
    @suggestion_lines = Accounting::JournalEntryLine.where(id: @suggestions.flat_map(&:line_ids)).includes(:journal_entry).index_by(&:id)
    @letterings = Accounting::Lettering.where(account: @account).includes(:partner).order(code: :desc).limit(20)
    @allocations = Accounting::LineAllocation.where(debit_line_id: @lines.map(&:id)).includes(debit_line: :journal_entry, credit_line: %i[journal_entry partner])
  end
end

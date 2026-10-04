# F04: the proposed letterings. Accepting one letters its lines (or books the rounding entry of a rule-6 proposal); a batch is
# previewed first and letters nothing until confirmed.
class Accounting::LetteringSuggestionsController < ApplicationController
  before_action { authorize Accounting::Lettering, :create? }

  def create
    Accounting::SuggestLetterings.call
    redirect_to back_path, notice: "Suggestions refreshed"
  end

  def accept
    suggestion = Accounting::LetteringSuggestion.find(params[:id])
    result = Accounting::AcceptLetteringSuggestion.call(suggestion: suggestion, user: current_user)
    redirect_to back_path(suggestion.account_id), result.success? ? { notice: "Suggestion accepted" } : { alert: result.message }
  end

  def reject
    suggestion = Accounting::LetteringSuggestion.find(params[:id])
    suggestion.reject!(current_user)
    redirect_to back_path(suggestion.account_id), notice: "Suggestion rejected"
  end

  def preview
    @suggestions = chosen.includes(:account, :partner)
    @lines = Accounting::JournalEntryLine.where(id: @suggestions.flat_map(&:line_ids)).includes(:journal_entry).index_by(&:id)
  end

  def accept_batch
    results = chosen.map { |s| [ s, Accounting::AcceptLetteringSuggestion.call(suggestion: s, user: current_user) ] }
    failed  = results.select { |_, r| r.failure? }
    flash[:notice] = "#{results.size - failed.size} suggestion(s) accepted"
    flash[:alert]  = "#{failed.size} could not be applied: #{failed.map { |_, r| r.message }.uniq.to_sentence}" if failed.any?
    redirect_to back_path(results.first&.first&.account_id)
  end

  private

  def chosen = Accounting::LetteringSuggestion.proposed.where(id: Array(params[:suggestion_ids])).order(score: :desc, id: :asc)

  def back_path(account_id = params[:account_id]) = new_accounting_lettering_path(account_id: account_id)
end

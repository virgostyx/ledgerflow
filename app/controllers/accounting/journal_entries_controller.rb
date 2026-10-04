class Accounting::JournalEntriesController < ApplicationController
  before_action :set_entry, only: [ :show, :edit, :update, :post_entry, :reverse, :reversal, :duplicate ]

  def index
    @pagy, @entries = pagy(policy_scope(Accounting::JournalEntry).includes(:journal).filter_by(filter_params).order(entry_date: :desc, created_at: :desc).autofilter(**autofilter_params))
  end

  def show
    authorize @entry
    @period_lock = Accounting::PeriodLock.covering(@entry.entry_date).first if feature?(:f01)
  end

  def new
    @entry      = Accounting::JournalEntry.new
    @entry.fiscal_year = Accounting::FiscalYear.current
    @journals   = Accounting::Journal.active.order(:code)
    @accounts   = Accounting::Account.where(is_leaf: true).order(:code)
    @axes       = Accounting::AnalyticalAxis.active.ordered.includes(analytical_accounts: [])
    authorize @entry
  end

  def create
    converted = converted_entry_params
    return render_foreign_error(:new) if @fx_error

    @entry = Accounting::JournalEntry.new(converted.merge(created_by: current_user))
    authorize @entry

    saved = ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      @entry.save
    end

    if saved && !policy(@entry).post?
      # Whoever may only draft (an assistant) never validates: the entry waits for someone who may.
      redirect_to accounting_journal_entry_path(@entry), notice: t("accounting.journal_entries.created")
      return
    end

    if saved && @entry.four_eyes_blocks?(current_user)
      # The entity requires a second person: the author's entry waits as a draft.
      redirect_to accounting_journal_entry_path(@entry), notice: t("accounting.journal_entries.saved_for_review")
      return
    end

    if saved
      result = Accounting::PostJournalEntry.call(entry: @entry)
      if result.success?
        redirect_to accounting_journal_entry_path(@entry),
                    notice: t("accounting.journal_entries.posted")
        return
      else
        @entry.destroy
        flash.now[:alert] = result.message
      end
    end

    @journals = Accounting::Journal.active.order(:code)
    @accounts = Accounting::Account.where(is_leaf: true).order(:code)
    @axes     = Accounting::AnalyticalAxis.active.ordered.includes(analytical_accounts: [])
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @entry
    @journals = Accounting::Journal.active.order(:code)
    @accounts = Accounting::Account.where(is_leaf: true).order(:code)
    @axes     = Accounting::AnalyticalAxis.active.ordered.includes(analytical_accounts: [])
  end

  def update
    authorize @entry
    converted = converted_entry_params
    return render_foreign_error(:edit) if @fx_error

    if @entry.update(converted)
      redirect_to accounting_journal_entry_path(@entry),
                  notice: t("accounting.journal_entries.updated")
    else
      @journals = Accounting::Journal.active.order(:code)
      @accounts = Accounting::Account.where(is_leaf: true).order(:code)
      @axes     = Accounting::AnalyticalAxis.active.ordered.includes(analytical_accounts: [])
      render :edit, status: :unprocessable_content
    end
  end

  def post_entry
    authorize @entry, :post?
    result = Accounting::PostJournalEntry.call(entry: @entry)
    if result.success?
      redirect_to accounting_journal_entry_path(@entry),
                  notice: t("accounting.journal_entries.posted")
    else
      redirect_to accounting_journal_entry_path(@entry), alert: result.message
    end
  end

  # Preview of the reversal: inverse lines, date it will have, warnings (period, VAT, closed year, lettering).
  def reversal
    authorize @entry, :reverse?
    @preview = Accounting::ReverseJournalEntry.preview(@entry, date: params[:date].presence)
  end

  def duplicate
    authorize Accounting::JournalEntry, :create?
    result = Accounting::DuplicateJournalEntry.call(entry: @entry, user: current_user)
    if result.success?
      redirect_to edit_accounting_journal_entry_path(result[:entry]), notice: "Draft copy of #{@entry.reference || 'the entry'} created"
    else
      redirect_to accounting_journal_entry_path(@entry), alert: result.message
    end
  end

  def reverse
    authorize @entry, :reverse?
    result = Accounting::ReverseJournalEntry.call(entry: @entry, reason: params[:reason], date: params[:date].presence,
                                                  confirm_unletter: params[:confirm_unletter] == "1", user: current_user)
    if result.success?
      redirect_to accounting_journal_entry_path(result[:reversal]),
                  notice: ([ t("accounting.journal_entries.reversed", reference: result[:reversal].reference) ] + result[:warnings]).join(" ")
    else
      redirect_to accounting_journal_entry_path(@entry), alert: result.message
    end
  end

  private

  def set_entry
    @entry = Accounting::JournalEntry.includes(lines: [ :account, :partner ]).find(params[:id])
  end

  # The lines in a foreign currency, as the form sends them, become euros at the rate of the entry date (Fx::EntryLines); a refusal (no rate for the
  # currency and the date, a rate typed without right) is `@fx_error`, and nothing is saved.
  def converted_entry_params
    permitted = entry_params
    lines = permitted[:lines_attributes]
    return permitted if lines.blank?

    date = (Date.iso8601(permitted[:entry_date].to_s) rescue Date.current)
    result = Fx::EntryLines.call(lines.to_h, date: date, reason: params.dig(:accounting_journal_entry, :fx_rate_reason), user: current_user)
    @fx_error = result.error
    flash.now[:notice] = result.warning if result.warning
    @fx_error ? permitted : permitted.merge(lines_attributes: result.lines)
  end

  def render_foreign_error(view)
    @entry ||= Accounting::JournalEntry.new(entry_params.except(:lines_attributes))
    authorize @entry, view == :new ? :create? : :update?
    @journals = Accounting::Journal.active.order(:code)
    @accounts = Accounting::Account.where(is_leaf: true).order(:code)
    @axes     = Accounting::AnalyticalAxis.active.ordered.includes(analytical_accounts: [])
    flash.now[:alert] = @fx_error
    render view, status: :unprocessable_content
  end

  def entry_params
    params.require(:accounting_journal_entry).permit(
      :journal_id, :fiscal_year_id, :entry_date, :description, :auto_reverse_on,
      lines_attributes: [
        :id, :account_id, :partner_id, :debit, :credit, :label, :vat_code, :vat_amount, :_destroy, :currency, :amount_currency, :exchange_rate, :side,
        analytical_annotations_attributes: [ :id, :analytical_axis_id, :analytical_account_id, :_destroy ]
      ]
    )
  end
end

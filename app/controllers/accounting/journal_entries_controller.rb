class Accounting::JournalEntriesController < ApplicationController
  before_action :set_entry, only: [ :show, :edit, :update, :post_entry, :reverse ]

  def index
    @entries = policy_scope(Accounting::JournalEntry).order(entry_date: :desc, created_at: :desc)
  end

  def show
    authorize @entry
  end

  def new
    @entry      = Accounting::JournalEntry.new
    @entry.fiscal_year = Accounting::FiscalYear.find_by(status: :open)
    @journals   = Accounting::Journal.active.order(:code)
    @accounts   = Accounting::Account.where(is_leaf: true).order(:code)
    authorize @entry
  end

  def create
    @entry = Accounting::JournalEntry.new(entry_params)
    authorize @entry

    saved = ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      @entry.save
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
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @entry
    @journals = Accounting::Journal.active.order(:code)
    @accounts = Accounting::Account.where(is_leaf: true).order(:code)
  end

  def update
    authorize @entry
    if @entry.update(entry_params)
      redirect_to accounting_journal_entry_path(@entry),
                  notice: t("accounting.journal_entries.updated")
    else
      @journals = Accounting::Journal.active.order(:code)
      @accounts = Accounting::Account.where(is_leaf: true).order(:code)
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

  def reverse
    authorize @entry, :reverse?
    redirect_to accounting_journal_entry_path(@entry),
                alert: t("accounting.journal_entries.reverse_not_implemented")
  end

  private

  def set_entry
    @entry = Accounting::JournalEntry.find(params[:id])
  end

  def entry_params
    params.require(:accounting_journal_entry).permit(
      :journal_id, :fiscal_year_id, :entry_date, :description,
      lines_attributes: [ :id, :account_id, :debit, :credit, :label, :vat_code, :vat_amount, :_destroy ]
    )
  end
end

class Api::V1::JournalEntriesController < Api::V1::BaseController
  def index
    entries = Accounting::JournalEntry.all
    entries = entries.where(project_id: params[:project_id]) if params[:project_id].present?
    entries = entries.where(fiscal_year_id: params[:fiscal_year_id]) if params[:fiscal_year_id].present?
    entries = entries.order(entry_date: :desc)
    render json: entries.map { |e| serialize_entry(e) }
  end

  def show
    entry = Accounting::JournalEntry.find(params[:id])
    render json: serialize_entry(entry)
  end

  def create
    account = Accounting::Account.find_by(code: params[:account_code])
    return render json: { error: "Account not found" }, status: :unprocessable_content if account.nil?

    journal     = Accounting::Journal.where(journal_type: :purchase, active: true).first
    fiscal_year = Accounting::FiscalYear.find_by(status: :open)
    amount      = BigDecimal(params[:amount].to_s)

    entry = nil
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = Accounting::JournalEntry.create!(
        journal:     journal,
        fiscal_year: fiscal_year,
        entry_date:  Date.parse(params[:date].to_s),
        description: params[:description],
        project_id:  params[:project_id],
        status:      :draft
      )
      Accounting::JournalEntryLine.create!(
        journal_entry: entry, account: account,
        debit: amount, credit: BigDecimal("0"), label: params[:description]
      )
      Accounting::JournalEntryLine.create!(
        journal_entry: entry, account: journal.default_account,
        debit: BigDecimal("0"), credit: amount, label: params[:description]
      )
    end

    result = Accounting::PostJournalEntry.call(entry: entry)
    if result.success?
      render json: serialize_entry(entry.reload), status: :created
    else
      entry.destroy
      render json: { error: result.message }, status: :unprocessable_content
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def serialize_entry(entry)
    {
      id:          entry.id,
      reference:   entry.reference,
      status:      entry.status,
      entry_date:  entry.entry_date,
      description: entry.description,
      project_id:  entry.project_id
    }
  end
end

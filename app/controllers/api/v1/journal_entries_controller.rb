# Read-only. Accounting data enters through /invoices (docs/dev/api/inbound-api.md), never as ad-hoc entries.
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

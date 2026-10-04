# F09: one customer's reminder: the text, the lines it covers and the statement; edit it, leave it out, change its level (a skip needs confirming),
# print its letter, record a bounce reported by the mail server.
class Accounting::DunningItemsController < ApplicationController
  before_action { require_feature!(:f09) }
  before_action :set_item

  def show
    authorize @item, :show?, policy_class: Accounting::DunningRunPolicy
    @statement = Accounting::DunningStatement.new(partner: @item.partner, as_of: @item.run_on)
    @lines = @item.item_lines.includes(line: :journal_entry).sort_by(&:due_date)
  end

  def update
    authorize @item, :update?, policy_class: Accounting::DunningRunPolicy
    result = Accounting::UpdateDunningItem.call(item: @item, **item_params)
    redirect_to accounting_dunning_item_path(@item), (result.success? ? { notice: t("accounting.dunning.item_updated") } : { alert: result.message })
  end

  def pdf
    authorize @item, :show?, policy_class: Accounting::DunningRunPolicy
    send_data Accounting::DunningPdf.new(@item, letter: @item.letter?).render, type: "application/pdf", disposition: "inline", filename: "reminder-#{@item.partner_id}-#{@item.run_on}.pdf"
  end

  def bounce
    authorize @item, :bounce?, policy_class: Accounting::DunningRunPolicy
    result = Accounting::RecordDunningBounce.call(item: @item, reason: params[:reason])
    redirect_to accounting_dunning_item_path(@item), (result.success? ? { notice: t("accounting.dunning.bounce_recorded") } : { alert: result.message })
  end

  private

  def set_item = @item = Accounting::DunningItem.find(params[:id])

  def item_params
    permitted = params.require(:accounting_dunning_item).permit(:level, :recipient, :subject, :body, :excluded, :skip_confirmed).to_h.symbolize_keys
    permitted[:level] = permitted[:level].to_i if permitted[:level].present?
    permitted.delete(:level) if permitted[:level].blank?
    permitted
  end
end

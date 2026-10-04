# F06 step 4: what went through Peppol. « Received » (to look at, work on again, give its supplier, put aside), « Sent » (to follow, to send again),
# and a board of the period.
class Accounting::PeppolMessagesController < ApplicationController
  before_action :set_message, only: %i[show pdf reprocess dismiss assign_supplier resend]
  before_action -> { authorize Accounting::PeppolMessage, :index?, policy_class: Accounting::PeppolMessagePolicy }, except: :resend
  before_action -> { authorize Accounting::PeppolMessage, :resend?, policy_class: Accounting::PeppolMessagePolicy }, only: :resend

  def index
    @direction = params[:direction] == "outbound" ? "outbound" : "inbound"
    @period = period
    @messages = scope.where(direction: @direction).order(occurred_at: :desc, id: :desc).includes(:invoice)
    @messages = @messages.where(status: params[:status]) if Accounting::PeppolMessage.statuses.key?(params[:status].to_s)
    @messages = @messages.where(occurred_at: @period) if params[:from].present? || params[:to].present?
    @pagy, @messages = pagy(@messages)
    @board = board
  end

  def show
    @readable = readable
    @pdf = Peppol::EmbeddedPdf.find(@message.xml).present?
    @suppliers = Accounting::Partner.supplier.order(:name).limit(500) if @message.needs_review?
  end

  # The PDF the supplier embedded, served from the message itself (the invoice may not exist: the message waits).
  def pdf
    pdf = Peppol::EmbeddedPdf.find(@message.xml) or return head(:not_found)
    send_data pdf[:bytes], type: "application/pdf", disposition: "inline", filename: pdf[:filename] || "document.pdf"
  end

  def reprocess
    result = Peppol::MessageActions.reprocess(message: @message, user: current_user)
    redirect_to accounting_peppol_message_path(@message), result.success? ? { notice: outcome(@message.reload) } : { alert: result.message }
  end

  # Several at once, after the cause they share was dealt with (a VAT category mapped, an exchange rate entered).
  def reprocess_all
    messages = scope.where(id: Array(params[:message_ids]), status: %i[needs_review received]).includes(:partner).to_a
    done = messages.count { |m| Peppol::MessageActions.reprocess(message: m, user: current_user).success? && m.reload.processed? }
    redirect_to accounting_peppol_messages_path(status: "needs_review"), notice: "#{done} of #{messages.size} message(s) drafted"
  end

  def assign_supplier
    partner = Accounting::Partner.find(params[:partner_id])
    result = Peppol::MessageActions.assign_supplier(message: @message, partner: partner, user: current_user)
    redirect_to accounting_peppol_message_path(@message), result.success? ? { notice: outcome(@message.reload) } : { alert: result.message }
  end

  def dismiss
    result = Peppol::MessageActions.dismiss(message: @message, user: current_user, reason: params[:reason])
    redirect_to accounting_peppol_message_path(@message), result.success? ? { notice: "Message put aside" } : { alert: result.message }
  end

  # An invoice that failed on its way is sent again (the same checks as the first time, the Access Point adopts what it already has).
  def resend
    invoice = @message.invoice
    return redirect_to(accounting_peppol_message_path(@message), alert: "Only a sent invoice that failed can be sent again") unless @message.outbound? && @message.failed? && invoice

    result = Peppol::SendInvoice.call(invoice: invoice)
    Accounting::AuditLog.record!(auditable: invoice, action: "peppol_resent", user: current_user, payload: { message_id: @message.message_id, success: result.success? })
    redirect_to accounting_peppol_message_path(@message), result.success? ? { notice: "Sent again" } : { alert: result.message }
  end

  private

  def set_message = @message = scope.find(params[:id])

  def scope = Accounting::PeppolMessage.all

  def outcome(message) = message.processed? ? "Drafted: #{message.invoice&.external_ref || 'invoice'}" : "Still waiting: #{message.problems.join(' ')}"

  # The period of the board and of the date filters: the month by default.
  def period
    parse_date(params[:from], Date.current.beginning_of_month).beginning_of_day..parse_date(params[:to], Date.current.end_of_month).end_of_day
  end

  def parse_date(value, default)
    Date.iso8601(value.to_s)
  rescue Date::Error
    default
  end

  def board
    messages = Accounting::PeppolMessage.where(occurred_at: @period)
    inbound = messages.inbound
    outbound = messages.outbound
    { received: inbound.count, drafted: inbound.processed.count, waiting: Accounting::PeppolMessage.inbound.needs_review.count,
      sent: outbound.count, delivered: outbound.delivered.count, failed: outbound.failed.count }
  end

  def readable
    Peppol::InvoiceMapper.call(@message.xml)
  rescue Peppol::InvoiceMapper::Unreadable
    nil
  end
end

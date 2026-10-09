class Accounting::InvoicesController < ApplicationController
  before_action :set_invoice, only: [ :peppol_fallback_email, :show, :edit, :update, :destroy, :validate_invoice, :cancel_invoice, :return_invoice, :send_peppol,
                                      :create_credit_note, :apply_credit_note, :pdf, :document, :send_email, :duplicate, :submit_for_approval ]
  before_action :set_invoice_type_context, only: [ :index, :new, :create ]

  def index
    @pagy, @invoices = pagy(policy_scope(Accounting::Invoice)
                              .includes(:journal, :partner)
                              .then { |rel| budgetflow_enabled? ? rel.includes(:ubl_document_attachment) : rel }
                              .where(invoice_type: @invoice_type)
                              .filter_by(budgetflow_enabled? ? filter_params : filter_params.except(:source))
                              .order(invoice_date: :desc)
                              .autofilter(**autofilter_params))
    @budgetflow_to_process = policy_scope(Accounting::Invoice).external.draft.supplier.count if budgetflow_enabled? && @invoice_type == "supplier"
  end

  def show
    authorize @invoice
    @period_lock = Accounting::PeriodLock.covering(@invoice.invoice_date).first if feature?(:f01) && @invoice.invoice_date
  end

  def new
    @invoice = Accounting::Invoice.new(invoice_type: @invoice_type, invoice_date: Date.current)
    if @invoice_type.present?
      journal_type = @invoice.customer? ? :sale : :purchase
      @invoice.journal = Accounting::Journal.active.find_by(journal_type: journal_type)
    end
    @invoice.lines.build
    @next_entry_number = preview_next_sequence(@invoice.journal)
    @axes     = Accounting::AnalyticalAxis.active.order(:code)
    @accounts = Accounting::Account.active.where(is_leaf: true).order(:code)
    authorize @invoice
  end

  def create
    @invoice = Accounting::Invoice.new(invoice_params.merge(invoice_type: @invoice_type, created_by: current_user))
    authorize @invoice

    if @invoice.save
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.created")
    else
      @axes     = Accounting::AnalyticalAxis.active.order(:code)
      @accounts = Accounting::Account.active.where(is_leaf: true).order(:code)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @axes     = Accounting::AnalyticalAxis.active.order(:code)
    @accounts = Accounting::Account.active.where(is_leaf: true).order(:code)
    authorize @invoice
  end

  def update
    authorize @invoice

    if @invoice.update(invoice_params)
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.updated")
    else
      @axes     = Accounting::AnalyticalAxis.active.order(:code)
      @accounts = Accounting::Account.active.where(is_leaf: true).order(:code)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @invoice

    invoice_type = @invoice.invoice_type
    if @invoice.draft?
      @invoice.destroy!
      redirect_to list_path_for(invoice_type), notice: t("accounting.invoices.deleted")
    else
      head :unprocessable_content
    end
  end

  # B01a: puts a purchase invoice to approval by hand (a draft too), or records that it needs none.
  def submit_for_approval
    authorize @invoice
    result = Approvals::Submit.call(invoice: @invoice, user: current_user)
    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t(result[:request] ? "approvals.submitted" : "approvals.not_required")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def cancel_invoice
    authorize @invoice, :cancel?

    result = Accounting::CancelInvoice.call(invoice: @invoice)
    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.cancelled")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def return_invoice
    return head(:not_found) unless budgetflow_enabled? # the action does not exist for other entities

    authorize @invoice, :return_to_sender?

    result = Accounting::ReturnInvoice.call(invoice: @invoice, reason: params[:reason])
    if result.success?
      redirect_to accounting_purchases_path, notice: t("accounting.invoices.returned")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def validate_invoice
    authorize @invoice, :post?

    result = Accounting::PostInvoice.call(invoice: @invoice)

    if result.success?
      flash[:alert] = result[:rate_warning] if result[:rate_warning] # a typed rate far from the official one (F11)
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.posted")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def create_credit_note
    authorize @invoice

    unless @invoice.invoice? && @invoice.issued?
      return redirect_to accounting_invoice_path(@invoice), alert: t("accounting.invoices.errors.credit_note_needs_posted")
    end

    note = @invoice.build_credit_note(created_by: current_user)
    if note.save
      redirect_to edit_accounting_invoice_path(note), notice: t("accounting.invoices.credit_note_created")
    else
      redirect_to accounting_invoice_path(@invoice), alert: note.errors.full_messages.to_sentence
    end
  end

  def apply_credit_note
    authorize @invoice

    result = Accounting::ApplyCreditNote.call(credit_note: @invoice)
    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.credit_note_applied")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def duplicate
    authorize @invoice

    result = Accounting::DuplicateInvoice.call(invoice: @invoice, created_by: current_user)
    if result.success?
      redirect_to edit_accounting_invoice_path(result[:invoice]), notice: t("accounting.invoices.duplicated")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  def send_email
    authorize @invoice

    result = Accounting::SendInvoiceEmail.call(invoice: @invoice, recipient: params[:recipient], user: current_user)
    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.email_queued", recipient: result[:email].recipient)
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  # The documents kept from a Peppol invoice: the original UBL XML (download) and the PDF the supplier embedded (in the browser).
  def document
    authorize @invoice, :show?

    attachment = { "xml" => @invoice.ubl_document, "pdf" => @invoice.pdf_document }[params[:kind]]
    return head(:not_found) unless attachment&.attached?

    send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type,
                                   disposition: params[:kind] == "pdf" ? "inline" : "attachment"
  end

  def pdf
    authorize @invoice

    error = if !@invoice.customer? then "pdf_customer_only"
    elsif !@invoice.issued?        then "pdf_not_issued"
    end
    return redirect_to accounting_invoice_path(@invoice), alert: t("accounting.invoices.errors.#{error}") if error

    send_data Accounting::InvoicePdf.new(@invoice).render, type: "application/pdf", disposition: :inline,
              filename: "#{@invoice.invoice_number.tr('/', '-')}.pdf"
  end

  def send_peppol
    authorize @invoice, :send_peppol?

    result = Peppol::SendInvoice.call(invoice: @invoice)
    Accounting::AuditLog.record!(auditable: @invoice, action: "peppol_sent", user: current_user, payload: { success: result.success?, error: (result.message unless result.success?) })

    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t(result[:retrying] ? "peppol.invoices.retrying" : "peppol.invoices.sent")
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  # The buyer is not reachable through Peppol (not registered, no identifier): the PDF goes to its e-mail address instead, and the audit trail says
  # that the e-mail replaced the network.
  def peppol_fallback_email
    authorize @invoice, :send_peppol?
    recipient = @invoice.partner.email
    return redirect_to(accounting_invoice_path(@invoice), alert: t("peppol.errors.no_buyer_email", partner: @invoice.partner.name)) if recipient.blank?

    result = Accounting::SendInvoiceEmail.call(invoice: @invoice, recipient: recipient, user: current_user)
    Accounting::AuditLog.record!(auditable: @invoice, action: "peppol_fallback_email", user: current_user, payload: { recipient: recipient, success: result.success? })
    if result.success?
      redirect_to accounting_invoice_path(@invoice), notice: t("accounting.invoices.email_queued", recipient: recipient)
    else
      redirect_to accounting_invoice_path(@invoice), alert: result.message
    end
  end

  private

  def set_invoice
    @invoice = Accounting::Invoice.find(params[:id])
  end

  def set_invoice_type_context
    @invoice_type = params[:invoice_type].presence
  end

  def preview_next_sequence(journal)
    return nil unless journal
    year = Date.current.year
    next_seq = journal.current_sequence + 1
    "#{journal.sequence_prefix}#{year}/#{next_seq.to_s.rjust(4, '0')}"
  end

  def list_path_for(invoice_type)
    invoice_type.to_s == "customer" ? accounting_sales_path : accounting_purchases_path
  end

  def invoice_params
    params.require(:accounting_invoice).permit(
      :invoice_date, :due_date, :partner_id, :journal_id, :cash_journal_id,
      :fiscal_year_id, :currency, :exchange_rate, :exchange_rate_reason, :description, :notes, :external_ref, :vat_treatment,
      lines_attributes: [
        :id, :description, :account_id, :quantity, :unit_price,
        :vat_rate, :vat_code, :position, :_destroy,
        analytical_annotations_attributes: [
          :id, :analytical_axis_id, :analytical_account_id, :_destroy
        ]
      ]
    )
  end
end

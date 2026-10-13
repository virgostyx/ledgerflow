# Where a payment stands, from the invoice received to its lettering (B01c §6 "Frise d'un paiement"), with who did each step and when. A step not reached yet is shown as to come.
# `for_batch` follows a batch; `for_invoice` follows the payment of an invoice (its last payment) and shows the steps before the batch too.
module Payments::Timeline
  Step = Struct.new(:label, :at, :by, :note, keyword_init: true) do
    def done? = !at.nil?
  end

  def self.for_batch(batch)
    posted = audit(batch, "payment_batch_entries_posted")
    [
      Step.new(label: "Prepared", at: batch.prepared_at, by: batch.prepared_by&.full_name),
      Step.new(label: "Approved", at: approved_at(batch), by: approver(batch)),
      Step.new(label: "File made", at: batch.exported_at, by: batch.exported_by&.full_name, note: batch.file_sha256&.first(12)),
      Step.new(label: "Loaded in the bank", at: batch.submitted_at, by: batch.submitted_by&.full_name),
      Step.new(label: "Debited", at: batch.debited_at, by: batch.debited_by&.full_name, note: debit_note(batch)),
      Step.new(label: "Payments validated", at: posted&.created_at, by: posted&.user&.full_name),
      Step.new(label: "Invoices lettered", at: (posted&.created_at if posted && posted.payload["lettered"].to_i.positive?), by: posted&.user&.full_name,
               note: (posted && "#{posted.payload['lettered']} lettered"))
    ]
  end

  def self.for_invoice(invoice)
    request = Approvals::Request.where(subject: invoice, status: :approved).order(:id).last
    link = Payments::ItemInvoice.where(invoice_id: invoice.id).includes(item: :batch).order(:id).last
    before = [
      Step.new(label: "Invoice received", at: invoice.created_at, by: invoice.created_by&.full_name),
      Step.new(label: "Approved", at: request&.decided_at, by: request && request.decisions.approved.last&.approver&.full_name, note: ("No approval needed" if request.nil? && invoice.payment_not_required?))
    ]
    return before + [ "In a batch", "File made", "Loaded in the bank", "Debited", "Payments validated", "Lettered" ].map { |label| Step.new(label: label) } if link.nil?

    batch = link.item.batch
    in_batch = Step.new(label: "In batch #{batch.reference}", at: link.created_at, by: batch.prepared_by&.full_name)
    rest = for_batch(batch).drop(2)
    lettered = rest.pop
    before + [ in_batch ] + rest + [ Step.new(label: "Lettered", at: (lettered.at if invoice.paid?), by: lettered.by) ]
  end

  def self.audit(batch, action) = Accounting::AuditLog.for_record(batch).for_action(action).order(:id).last
  private_class_method :audit

  def self.approved_at(batch) = (batch.approval_request.decided_at if batch.approval_request&.approved?)
  private_class_method :approved_at

  def self.approver(batch) = (batch.approval_request.decisions.approved.last&.approver&.full_name if batch.approval_request&.approved?)
  private_class_method :approver

  def self.debit_note(batch)
    return unless batch.debited_at

    batch.debit_kind == "manual" ? "By hand: #{batch.debit_reason} (#{batch.debit_reference})" : "From the statement"
  end
  private_class_method :debit_note
end

# Settles a posted credit note against the invoice it credits, through the existing partial lettering.
class Accounting::ApplyCreditNote
  TRADE_ACCOUNTS = Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS

  def self.call(credit_note:)
    original = credit_note.credited_invoice
    error = if !(credit_note.credit_note? && original)  then "credit_note_needs_invoice"
    elsif original.paid_amount.positive?                 then "credit_note_invoice_has_receipts" # receipts sit on their own lines: settle by hand
    end
    return LightService::Context.make(credit_note: credit_note).tap { |c| c.fail!(I18n.t("accounting.invoices.errors.#{error}")) } if error

    Accounting::AllocateLines.call(lines: [ trade_line(credit_note), trade_line(original) ])
  end

  def self.trade_line(invoice)
    invoice.journal_entry.lines.joins(:account).find_by!(accounting_accounts: { code: TRADE_ACCOUNTS })
  end
  private_class_method :trade_line
end

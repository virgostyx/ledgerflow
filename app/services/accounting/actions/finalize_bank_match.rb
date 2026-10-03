# F02: validating the draft payment entry of a matched bank line settles the line and pays the invoices the payment covers.
class Accounting::Actions::FinalizeBankMatch
  extend LightService::Action

  expects :entry

  # Both halves of a transfer between own accounts are validated: their transit lines cancel out, they are lettered. A lettering that
  # fails never undoes the validation: the lines stay open on the lettering screen.
  def self.letter_transfer(transaction)
    return unless transaction.match_data["kind"] == "transfer"

    other = Accounting::BankTransaction.find_by(id: transaction.match_data["pair_id"])
    return unless other&.reconciled?

    lines = [ transaction.journal_entry, other.journal_entry ].flat_map { |entry| entry.lines.joins(:account).where(accounting_accounts: { code: Accounting::AccountCodes::INTERNAL_TRANSFERS }).to_a }
    Accounting::LetterLines.call(lines: lines)
  end

  # A supplier payment (a debit on 440000 tied to an invoice) is lettered with the invoice's own payable line, which pays the invoice.
  # Same rule as the validated flow of PayInvoiceFromTransaction; a failing lettering leaves the lines open for the lettering screen.
  def self.letter_supplier_payments(entry)
    suppliers = Accounting::Account.find_by(code: Accounting::AccountCodes::SUPPLIERS)
    entry.lines.where(account: suppliers).where("debit > 0").where.not(invoice_id: nil).includes(:invoice).each do |payment|
      invoice_line = payment.invoice.journal_entry&.lines&.find_by(account: suppliers)
      Accounting::LetterLines.call(lines: [ invoice_line, payment ]) if invoice_line && invoice_line.credit == payment.debit
    end
  end

  executed do |ctx|
    transaction = Accounting::BankTransaction.matched.find_by(journal_entry_id: ctx.entry.id)
    next unless transaction

    transaction.update!(status: :reconciled)
    letter_transfer(transaction)
    letter_supplier_payments(ctx.entry)
    ctx.entry.lines.where.not(invoice_id: nil).includes(:invoice).filter_map(&:invoice).uniq.each do |invoice|
      invoice.pay! if invoice.remaining_amount.zero? && (invoice.posted? || invoice.partially_paid?)
    end
  end
end

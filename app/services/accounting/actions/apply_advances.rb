# Once the invoice is posted, books what it settles of its supplier's advances: 440000 is debited and 409000 credited (in the currency of the invoice),
# and the debit is allocated to the payable line of the invoice, like a part payment. Fully settled: lettered, hence paid.
# An advance wholly consumed has its 409000 lines lettered together (the exchange difference, if any, is booked by the lettering, F11).
class Accounting::Actions::ApplyAdvances
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice
    pending = invoice.advance_allocations.reject(&:journal_entry_id)
    next if pending.empty?

    pending.each do |allocation|
      line = book(invoice, allocation)
      settled = Accounting::AllocateLines.call(lines: [ line, trade_line(invoice) ], foreign_currency: true)
      next ctx.fail_with_rollback!(settled.message) if settled.failure?
    end
    pending.map(&:advance).uniq.each { |advance| letter_if_consumed(ctx, advance) }
  end

  # The entry of one allocation; returns its debit line on 440000.
  def self.book(invoice, allocation)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: invoice.journal_entry.journal, fiscal_year: invoice.fiscal_year, entry_date: invoice.invoice_date, status: :draft,
      description: "Advance #{allocation.advance.invoice_number} settled by #{invoice.invoice_number} — #{invoice.partner.name}"
    )
    payable = line(entry, invoice, allocation, Accounting::AccountCodes::SUPPLIERS, :debit, invoice: invoice)
    line(entry, invoice, allocation, Accounting::AccountCodes::ADVANCES, :credit)
    Accounting::PostJournalEntry.call!(entry: entry)
    allocation.update!(journal_entry: entry)
    payable
  end

  def self.line(entry, invoice, allocation, code, side, **attrs)
    eur = allocation.amount_eur
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: Accounting::Account.find_by!(code: code), partner: invoice.partner, label: invoice.partner.name,
      debit: side == :debit ? eur : 0, credit: side == :credit ? eur : 0,
      currency: invoice.currency, amount_currency: side == :debit ? allocation.amount : -allocation.amount, exchange_rate: invoice.exchange_rate, **attrs
    )
  end

  def self.trade_line(invoice)
    invoice.journal_entry.lines.joins(:account).find_by!(accounting_accounts: { code: Accounting::AccountCodes::SUPPLIERS })
  end

  # Nothing left to settle and nothing waiting in a draft: the advance and its settlements net out, letter them.
  def self.letter_if_consumed(ctx, advance)
    allocations = advance.consumptions.live.to_a
    return unless advance.advance_remaining.zero? && allocations.all?(&:journal_entry_id)

    advances_account = Accounting::Account.find_by!(code: Accounting::AccountCodes::ADVANCES)
    lines = Accounting::JournalEntryLine.where(account: advances_account, journal_entry_id: [ advance.journal_entry_id, *allocations.map(&:journal_entry_id) ]).to_a
    lettered = Accounting::LetterLines.call(lines: lines, settle: false, auto: true)
    ctx.fail_with_rollback!(lettered.message) if lettered.failure?
  end
  private_class_method :book, :line, :trade_line, :letter_if_consumed
end

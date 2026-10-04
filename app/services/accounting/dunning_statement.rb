# The statement of account of a customer (F09): all its open lines at `as_of` (R05, so the balance is R04's total for it), due or not, disputed or not.
class Accounting::DunningStatement
  attr_reader :rows

  def initialize(partner:, as_of:)
    @as_of = as_of
    @rows  = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: as_of).call.select { |r| r.partner_id == partner.id }
    @flags = Accounting::JournalEntryLine.where(id: @rows.map(&:line_id)).index_by(&:id)
  end

  def balance = rows.sum(&:residual)

  # What to say next to a line: why it is not asked for, or that it is a credit that stays on the statement without being deducted.
  def note(row, item)
    line = @flags.fetch(row.line_id)
    return "Credit not allocated: not deducted" if row.residual.negative?
    return "Disputed" if line.disputed
    return "Payment promised for #{Accounting::DatePresenter.new(line.payment_promised_on).format}" if line.payment_promised_on && line.payment_promised_on >= @as_of
    return "Covered by this reminder" if item.item_lines.any? { |l| l.line_id == row.line_id }

    "Not due for a reminder"
  end
end

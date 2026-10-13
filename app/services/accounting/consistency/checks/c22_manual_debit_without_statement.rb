# A payment batch whose debit was confirmed by hand and that no line of the statement is tied to (B01c §6): the money may have left the bank, but nothing proves it yet.
class Accounting::Consistency::Checks::C22ManualDebitWithoutStatement < Accounting::Consistency::Check
  self.check_id = "C22"
  self.severity = "warning"
  self.title = "Debit confirmed by hand, not found on a statement"

  def call
    Payments::Batch.where(status: :debited, debit_kind: "manual").includes(:items).select { |batch| batch.items.any? { |item| item.confirmed? && item.bank_transaction_id.nil? } }.map do |batch|
      finding(subject: batch, message: "#{batch.reference}: the debit was confirmed by hand on #{batch.debit_date&.strftime('%d/%m/%Y')} (bank reference #{batch.debit_reference}) and no line of a statement holds it yet",
              reference: batch.reference, bank_reference: batch.debit_reference)
    end
  end
end

# A lettered group whose lines do not sum to zero.
class Accounting::Consistency::Checks::C07UnbalancedLettering < Accounting::Consistency::Check
  self.check_id = "C07"
  self.severity = "blocking"
  self.title = "Lettered group with a non-zero total"

  def call
    Accounting::JournalEntryLine.where.not(lettering_id: nil).group(:lettering_id).having("SUM(debit) <> SUM(credit)")
                                .pluck(:lettering_id, Arel.sql("SUM(debit) - SUM(credit)")).map do |id, total|
      finding(subject: [ "Accounting::Lettering", id ], message: "Lettering ##{id} totals #{total} instead of 0", total: total)
    end
  end
end

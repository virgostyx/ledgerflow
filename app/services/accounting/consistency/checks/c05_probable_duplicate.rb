# Two live invoices with the same partner, external (issuer) reference, date and total. Our own invoice
# number is unique by constraint, so the partner's reference is what a duplicate entry shares.
class Accounting::Consistency::Checks::C05ProbableDuplicate < Accounting::Consistency::Check
  self.check_id = "C05"
  self.severity = "warning"
  self.title = "Probable duplicate invoice"

  def call
    Accounting::Invoice.where.not(status: Accounting::Invoice.statuses[:cancelled]).where.not(external_ref: [ nil, "" ])
      .group(:partner_id, :external_ref, :invoice_date, :total_incl_vat).having("COUNT(*) > 1")
      .pluck(:partner_id, :external_ref, :invoice_date, :total_incl_vat, Arel.sql("MIN(id)"), Arel.sql("COUNT(*)")).map do |partner_id, number, date, total, first_id, count|
      finding(subject: [ "Accounting::Invoice", first_id ], message: "#{count} invoices with reference #{number} dated #{date} for #{total} from the same partner",
              partner_id: partner_id, number: number, date: date.to_s, total: total, count: count)
    end
  end
end

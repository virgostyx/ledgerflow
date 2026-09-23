# Sums posted customer invoices under intracommunity treatment (goods/services) per partner,
# for the quarterly relevé intracommunautaire. Construction reverse charge and export/exempt
# sales are excluded — they're domestic or extra-EU, not subject to this listing.
class Accounting::IntracomListingQuery
  CODES = { "intracom_goods" => "L", "intracom_services" => "S" }.freeze

  def self.call(fiscal_year_id:, period_start:, period_end:)
    invoices = Accounting::Invoice
      .where(fiscal_year_id: fiscal_year_id, invoice_type: :customer,
             status: %w[posted paid partially_paid], vat_treatment: CODES.keys)
      .where(invoice_date: period_start..period_end)

    invoices.group_by { |inv| [ inv.partner_id, CODES.fetch(inv.vat_treatment) ] }
            .transform_values { |invs| invs.sum(&:total_incl_vat_eur) }
  end
end

# R10 listing annuel des clients assujettis (docs/dev/reports/spec.md §10): Belgian customers
# with domestic sales whose annual HTVA turnover exceeds `threshold` (250 € per the spec, to
# validate with an accountant). "Assujetti" is inferred from the VAT number — partners carry
# no such flag — so a customer above the threshold without a valid one is an anomaly, not
# silently dropped. Amounts are EUR, credit notes negative. No online VIES check.
class Accounting::AnnualCustomerListingQuery
  Row = Struct.new(:partner_id, :partner_name, :vat_number, :amount_excl_vat, :vat_amount, :anomalies, keyword_init: true)
  Result = Struct.new(:rows, :listed_total, :grids_total, keyword_init: true) do
    # The listing is a subset of the domestic sale bases (00-03), never more.
    def exceeds_grids? = listed_total > grids_total + BigDecimal("0.05")
  end

  def initialize(fiscal_year:, threshold: 250)
    @fiscal_year = fiscal_year
    @threshold   = threshold
  end

  def call
    rows = totals.filter_map do |partner_id, name, vat_number, excl, vat|
      next unless excl > @threshold

      Row.new(partner_id: partner_id, partner_name: name, vat_number: vat_number, amount_excl_vat: excl,
              vat_amount: vat, anomalies: anomalies_for(vat_number))
    end.sort_by(&:partner_name)

    Result.new(rows: rows, listed_total: rows.sum(BigDecimal("0"), &:amount_excl_vat), grids_total: grids_total)
  end

  private

  def totals
    sign = "CASE WHEN accounting_invoices.document_type = #{Accounting::Invoice.document_types[:credit_note]} THEN -1 ELSE 1 END"
    Accounting::Invoice.joins(:partner)
      .where(fiscal_year_id: @fiscal_year.id, invoice_type: :customer, vat_treatment: :domestic,
             status: %w[posted paid partially_paid], accounting_partners: { country: "BE" })
      .group("accounting_partners.id", "accounting_partners.name", "accounting_partners.vat_number")
      .pluck(Arel.sql("accounting_partners.id"), Arel.sql("accounting_partners.name"), Arel.sql("accounting_partners.vat_number"),
             Arel.sql("SUM(#{sign} * accounting_invoices.subtotal_excl_vat / accounting_invoices.exchange_rate)"),
             Arel.sql("SUM(#{sign} * accounting_invoices.vat_amount / accounting_invoices.exchange_rate)"))
      .map { |id, name, vat_number, excl, vat| [ id, name, vat_number, BigDecimal(excl.to_s).round(2), BigDecimal(vat.to_s).round(2) ] }
  end

  def anomalies_for(vat_number)
    return [ :no_vat_number ] if vat_number.blank?

    Accounting::BelgianVatNumber.valid?(vat_number) ? [] : [ :invalid_vat_number ]
  end

  # Base grids 00-03 of the year's VAT return figures (R09's source).
  def grids_total
    grids = Accounting::VatGridQuery.call(fiscal_year_id: @fiscal_year.id, period_start: @fiscal_year.start_date,
                                          period_end: @fiscal_year.end_date)
    %w[00 01 02 03].sum(BigDecimal("0")) { |g| grids[g] || 0 }
  end
end

require "csv"

# Aged balance as a BOM-prefixed CSV: one line per partner, then the totals line.
class Reports::Exporters::AgedBalanceCsv
  COLUMNS = (Accounting::AgedBalanceQuery::BUCKETS + %i[unallocated total overdue]).freeze

  def self.call(rows:, totals:) = new(rows, totals).call

  def initialize(rows, totals)
    @rows = rows
    @totals = totals
  end

  def call
    "﻿" + CSV.generate(headers: true) do |csv|
      csv << [ t(:partner), *COLUMNS.map { |c| t(c) }, t(:overdue_pct) ]
      @rows.each { |row| csv << line(row.partner_name || t(:no_partner), row) }
      csv << line(I18n.t("accounting.reports.totals"), @totals)
    end
  end

  private

  def line(label, source)
    [ label, *COLUMNS.map { |c| format("%.2f", source.public_send(c)) }, source.overdue_pct.nil? ? "" : format("%.1f", source.overdue_pct) ]
  end

  def t(key) = I18n.t("accounting.reports.aged_balance.#{key}")
end

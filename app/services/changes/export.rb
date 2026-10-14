# B03b R21: the report of changes as a file to hand to an auditor - CSV, XLSX, PDF - with the parameters, the two instants and the result of the closing. Built from the
# whole detail (not a page). The caller has checked the closing (Changes::ClosingGuard).
class Changes::Export
  Parameters = Struct.new(:attributes)

  COLUMNS = [
    [ "Validated at", ->(d) { d.at.utc.iso8601 } ], [ "Category", :category ], [ "Action", :action ], [ "Author", ->(d) { d.author.to_s } ], [ "Subject", :label ],
    [ "Amount", ->(d) { d.amount } ], [ "Reason", ->(d) { d.reason.to_s } ], [ "Neutral pair", ->(d) { d.neutral ? "yes" : "" } ],
    [ "Reviewed by", ->(d) { d.reviewed_by.to_s } ]
  ].freeze

  def initialize(report, fiscal_year:, watermark: nil)
    @report = report
    @fiscal_year = fiscal_year
    @watermark = watermark
  end

  def csv = Reports::Exporters::Csv.call(result, columns: COLUMNS)
  def xlsx = Reports::Exporters::Xlsx.call(result, columns: COLUMNS, title: "What changed")
  def pdf = Reports::Exporters::Pdf.call(result, columns: COLUMNS, title: title, watermark: @watermark)

  def filename(format) = "changes_#{stamp(@report.from)}_#{stamp(@report.to || Time.current)}.#{format}"

  # "Sum of variations = sum of movements, gap 0.00" (or the gap, which stops the export before it comes here).
  def closing_text = I18n.t("changes.closing.#{@report.closing.balanced? ? 'balanced' : 'gap'}", gap: format("%.2f", @report.closing.gap))

  private

  def stamp(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

  def title
    "What changed - from #{@report.from.utc.iso8601} to #{(@report.to || Time.current).utc.iso8601} (as of #{@report.as_of}) - #{closing_text}"
  end

  def result
    Reports::Result.new(rows: @report.details, filters: Parameters.new(attributes), warnings: [])
  end

  def attributes
    { "from" => @report.from.utc.iso8601(6), "to" => (@report.to || Time.current).utc.iso8601(6), "as_of" => @report.as_of.to_s, "fiscal_year" => @fiscal_year.year,
      "closing" => closing_text, "entries" => @report.summary.entries, "reversals" => @report.summary.reversals, "neutral_pairs" => @report.summary.neutral_pairs }
  end
end

# R20 closing bundle (docs/dev/reports/spec.md §13): a ZIP with the year's PDFs of R01, R02, R04, R07, R08,
# R09, R16 and R17, the frozen bank reconciliations of R06, the filing data, and a `manifest.json` giving the
# SHA-256 of every file and the generation date. Every figure comes from the same query objects as the
# screens. Files carry no timestamp, so two generations from the same data give identical files (only the
# manifest's `generated_at` differs).
class Accounting::ClosingBundle
  Result = Struct.new(:zip, :manifest, keyword_init: true)
  Verification = Struct.new(:checked, :mismatches, :missing, keyword_init: true) do
    def valid? = mismatches.empty? && missing.empty?
  end

  def self.call(fiscal_year:) = new(fiscal_year).call

  # Recomputes each file's hash against the manifest inside the ZIP.
  def self.verify(zip_data)
    contents = Accounting::Zipper.read(zip_data)
    manifest = JSON.parse(contents.fetch("manifest.json"))
    listed = manifest.fetch("files")
    mismatches = listed.reject { |f| contents.key?(f["path"]) && Digest::SHA256.hexdigest(contents[f["path"]]) == f["sha256"] }.map { |f| f["path"] }
    missing = listed.map { |f| f["path"] }.reject { |p| contents.key?(p) }
    Verification.new(checked: listed.size, mismatches: mismatches - missing, missing: missing)
  end

  def initialize(fiscal_year)
    @fiscal_year = fiscal_year
    @end = fiscal_year.end_date
  end

  def call
    files = pdfs + frozen_reconciliations + [ [ "filing_data.json", JSON.pretty_generate(Accounting::FilingData.call(fiscal_year: @fiscal_year)) ] ]
    manifest = { fiscal_year: @fiscal_year.year, generated_at: Time.current.utc.iso8601,
                 files: files.sort_by(&:first).map { |path, content| { path: path, sha256: Digest::SHA256.hexdigest(content), bytes: content.bytesize } } }
    Result.new(zip: Accounting::Zipper.build(files + [ [ "manifest.json", JSON.pretty_generate(manifest) ] ]), manifest: manifest)
  end

  private

  def pdfs
    [ [ "R01_trial_balance.pdf", trial_balance ], [ "R02_general_ledger.pdf", general_ledger ],
      [ "R04_aged_balance_customers.pdf", aged_balance(:customer) ], [ "R04_aged_balance_suppliers.pdf", aged_balance(:supplier) ],
      [ "R07_balance_sheet.pdf", annual(%i[assets liabilities], "Balance sheet") ], [ "R08_income_statement.pdf", annual(%i[income], "Income statement") ],
      [ "R09_vat_declarations.pdf", vat ], [ "R16_fixed_assets.pdf", fixed_assets ], [ "R17_regularizations.pdf", regularizations ] ]
  end

  def pdf(title, headers, rows)
    columns = headers.each_with_index.map { |h, i| [ h, ->(r) { r[i] } ] }
    Reports::Exporters::Pdf.call(Reports::Result.new(rows: rows), columns: columns, title: "#{title} — #{@fiscal_year.year}")
  end

  def trial_balance
    rows = Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @end).call
    pdf("Trial balance", %w[Code Label Opening\ debit Opening\ credit Debit Credit Closing\ debit Closing\ credit],
        rows.map { |r| [ r.code, r.label_fr, r.opening_display_debit, r.opening_display_credit, r.movement_debit, r.movement_credit, r.closing_display_debit, r.closing_display_credit ] })
  end

  def general_ledger
    account_ids = Accounting::PostedLine.where(fiscal_year_id: @fiscal_year.id).select(:account_id)
    rows = Accounting::Account.where(id: account_ids).order(:code).flat_map do |account|
      Accounting::GeneralLedgerQuery.new(account: account, fiscal_year: @fiscal_year).call.map do |l|
        [ account.code, l.entry_date, l.reference, l.label, l.debit, l.credit, l.running_balance ]
      end
    end
    pdf("General ledger", %w[Account Date Reference Label Debit Credit Balance], rows)
  end

  def aged_balance(kind)
    rows = Accounting::AgedBalanceQuery.new(kind: kind, as_of: @end).call
    pdf("Aged balance (#{kind}s) at #{@end}", %w[Partner Not\ due 1-30 31-60 61-90 >90 Unallocated Total],
        (rows + [ Accounting::AgedBalanceQuery.totals(rows) ]).map { |r| [ r.partner_name || "Total", *Accounting::AgedBalanceQuery::BUCKETS.map { |b| r.public_send(b) }, r.unallocated, r.total ] })
  end

  def annual(statements, title)
    report = Accounting::AnnualAccounts.new(fiscal_year: @fiscal_year).call
    rows = statements.flat_map { |s| report.rows(s).map { |r| [ s.to_s.humanize, r.code, r.label, r.amount, r.previous ] } }
    pdf(title, %w[Statement Code Label Amount Previous], rows)
  end

  def vat
    rows = Accounting::VatDeclaration.where(fiscal_year_id: @fiscal_year.id).order(:period_start).flat_map do |d|
      d.grids.sort.map { |code, amount| [ "#{d.period_start} – #{d.period_end}", d.status, code, Accounting::VatGrid.label(code), BigDecimal(amount.to_s) ] }
    end
    pdf("VAT declarations", %w[Period Status Grid Description Amount], rows)
  end

  def fixed_assets
    result = Accounting::FixedAssetMovementsQuery.new(fiscal_year: @fiscal_year).call
    rows = (result.categories + [ result.totals ]).map { |c| [ c.label, c.cost_begin, c.acquisitions, c.disposals, c.cost_end, c.dep_begin, c.dep_booked, c.dep_reversed, c.dep_end, c.net_value ] }
    pdf("Fixed-asset movements", %w[Category Cost\ start Acquisitions Disposals Cost\ end Dep.\ start Booked Reversed Dep.\ end Net\ value], rows)
  end

  def regularizations
    result = Accounting::AccrualsReportQuery.new(fiscal_year: @fiscal_year).call
    rows = result.rows.map { |r| [ r.accrual.accrual_type.humanize, r.accrual.description, r.accrual.total_amount, r.amount, r.status.to_s, r.missing_reversal ? "missing" : "ok" ] }
    rows += result.checks.map { |c| [ "Check (I11)", c.label, c.register, c.ledger, c.difference, "" ] }
    pdf("Closing regularizations", %w[Type Description Total At\ cut-off State Reversal], rows)
  end

  def frozen_reconciliations
    Accounting::BankReconciliationReport.where(as_of: @fiscal_year.start_date..@end).order(:as_of, :id).map do |report|
      [ "R06_bank_reconciliations/#{report.as_of}_bank-#{report.bank_account_id}_#{report.id}.json",
        JSON.pretty_generate({ bank_account_id: report.bank_account_id, as_of: report.as_of.to_s, content_hash: report.content_hash, result: report.result }) ]
    end
  end
end

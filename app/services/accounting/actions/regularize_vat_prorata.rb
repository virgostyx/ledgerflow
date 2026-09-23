# Year-end VAT prorata regularization for a mixed taxpayer (Entity#vat_prorata_rate).
# Compares the VAT actually deducted during the fiscal year (grid 59, computed at each
# invoice's own prorata) against the final prorata for the year, and posts the difference:
# grid 61 (to reverse, in the State's favor) or grid 62 (extra deduction recovered).
class Accounting::Actions::RegularizeVatProrata
  def self.call(fiscal_year_id:, final_prorata_rate:)
    ctx = LightService::Context.make(journal_entry: nil)
    fiscal_year = Accounting::FiscalYear.find(fiscal_year_id)

    already_deducted = deductible_vat_lines(fiscal_year).sum(:vat_amount)
    non_deductible   = non_deductible_lines(fiscal_year).sum(:debit)
    total_eligible   = already_deducted + non_deductible
    theoretical_deductible = (total_eligible * final_prorata_rate / 100).round(2)
    adjustment = theoretical_deductible - already_deducted

    ctx[:journal_entry] = post_adjustment(fiscal_year, adjustment) unless adjustment.zero?
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.deductible_vat_lines(fiscal_year)
    posted_lines(fiscal_year).where(vat_code: Accounting::VatGrid::VAT_LINE_GRID[:purchase])
  end

  def self.non_deductible_lines(fiscal_year)
    account = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_NON_DEDUCTIBLE)
    posted_lines(fiscal_year).where(account_id: account.id)
  end

  def self.posted_lines(fiscal_year)
    Accounting::JournalEntryLine.joins(:journal_entry).where(
      accounting_journal_entries: { fiscal_year_id: fiscal_year.id, status: Accounting::JournalEntry.statuses[:posted] }
    )
  end

  def self.post_adjustment(fiscal_year, adjustment)
    journal                 = Accounting::Journal.active.find_by!(journal_type: :misc)
    deductible_account      = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_DEDUCTIBLE)
    non_deductible_account  = Accounting::Account.find_by!(code: Accounting::AccountCodes::VAT_NON_DEDUCTIBLE)
    amount = adjustment.abs

    entry = Accounting::JournalEntry.new(
      journal:      journal,
      fiscal_year:  fiscal_year,
      entry_date:   fiscal_year.end_date,
      reference:    "VAT-PRORATA-#{fiscal_year.year}",
      description:  "Annual VAT prorata regularization #{fiscal_year.year}",
      status:       :draft
    )
    entry.save!

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

      if adjustment.positive? # more deductible than already claimed — recovered, grid 62
        create_line(entry, deductible_account, debit: amount, credit: 0, vat_code: 62, vat_amount: amount)
        create_line(entry, non_deductible_account, debit: 0, credit: amount)
      else # over-deducted during the year — must be reversed, grid 61
        create_line(entry, non_deductible_account, debit: amount, credit: 0)
        create_line(entry, deductible_account, debit: 0, credit: amount, vat_code: 61, vat_amount: amount)
      end

      entry.post!
    end

    entry
  end

  def self.create_line(entry, account, debit:, credit:, vat_code: nil, vat_amount: nil)
    Accounting::JournalEntryLine.create!(
      journal_entry: entry, account: account, debit: debit, credit: credit,
      label: "VAT prorata regularization", vat_code: vat_code, vat_amount: vat_amount
    )
  end

  private_class_method :deductible_vat_lines, :non_deductible_lines, :posted_lines,
                       :post_adjustment, :create_line
end

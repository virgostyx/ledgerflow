class Accounting::Actions::ComputeCarryForwardBalances
  extend LightService::Action

  BALANCE_SHEET_TYPES = [
    Accounting::Account.account_types[:asset],
    Accounting::Account.account_types[:liability],
    Accounting::Account.account_types[:equity]
  ].freeze

  RESULT_ACCOUNT_CODE       = "699000"
  CARRY_FORWARD_ACCOUNT_CODE = "130000"

  expects :previous_fiscal_year
  promises :carry_forward_lines, :carry_account

  executed do |ctx|
    unless ctx.previous_fiscal_year
      ctx[:carry_forward_lines] = []
      ctx[:carry_account]       = nil
      next ctx
    end

    carry_account = Accounting::Account.find_by(code: CARRY_FORWARD_ACCOUNT_CODE)
    unless carry_account
      ctx.fail!(I18n.t("accounting.fiscal_years.errors.missing_carry_account",
                       code: CARRY_FORWARD_ACCOUNT_CODE))
      next ctx
    end

    result_account = Accounting::Account.find_by(code: RESULT_ACCOUNT_CODE)

    # Balance sheet accounts + the net-result account (699000)
    account_scope = Accounting::Account.where(account_type: BALANCE_SHEET_TYPES)
    account_scope = account_scope.or(Accounting::Account.where(id: result_account.id)) if result_account

    candidate_ids = account_scope.pluck(:id)

    rows = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: ctx.previous_fiscal_year.id,
          status:         Accounting::JournalEntry.statuses[:posted]
        },
        account_id: candidate_ids
      )
      .group(:account_id)
      .select(
        "account_id",
        "SUM(debit)  AS total_debit",
        "SUM(credit) AS total_credit"
      )

    carry_forward_lines = []
    rows.each do |row|
      net = BigDecimal(row.total_debit.to_s) - BigDecimal(row.total_credit.to_s)
      next if net.zero?

      target_id = (result_account && row.account_id == result_account.id) ?
                    carry_account.id : row.account_id

      if net > 0
        carry_forward_lines << { account_id: target_id, debit: net,      credit: BigDecimal("0") }
      else
        carry_forward_lines << { account_id: target_id, debit: BigDecimal("0"), credit: net.abs }
      end
    end

    ctx[:carry_forward_lines] = carry_forward_lines
    ctx[:carry_account]       = carry_account
  end
end

class Accounting::Actions::ComputeCarryForwardBalances
  extend LightService::Action

  BALANCE_SHEET_TYPES = [
    Accounting::Account.account_types[:asset],
    Accounting::Account.account_types[:liability],
    Accounting::Account.account_types[:equity]
  ].freeze

  RESULT_ACCOUNT_CODE       = Accounting::AccountCodes::RESULT

  expects :previous_fiscal_year
  promises :carry_forward_lines, :carry_account

  executed do |ctx|
    unless ctx.previous_fiscal_year
      ctx[:carry_forward_lines] = []
      ctx[:carry_account]       = nil
      next ctx
    end

    entity = ActsAsTenant.current_tenant
    carry_account = Accounting::Account.find_by(code: entity.closing_carry_account_code)
    unless carry_account
      ctx.fail!(I18n.t("accounting.fiscal_years.errors.missing_carry_account",
                       code: entity.closing_carry_account_code))
      next ctx
    end
    # a loss goes to the loss account of the entity when its chart has it, else to the carry account itself
    loss_account = Accounting::Account.find_by(code: entity.closing_loss_account_code) || carry_account

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
          status:         Accounting::JournalEntry.ledger_status_values
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

      target_id = if result_account && row.account_id == result_account.id
                    (net > 0 ? loss_account : carry_account).id
      else
                    row.account_id
      end

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

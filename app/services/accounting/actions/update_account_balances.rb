class Accounting::Actions::UpdateAccountBalances
  extend LightService::Action

  expects :entry

  executed do |ctx|
    ctx.entry.lines.each do |line|
      Accounting::Account.update_counters(
        line.account_id,
        balance_debit:  line.debit,
        balance_credit: line.credit
      )
    end
  end
end

# Validated lines booked on an archived (inactive) account.
class Accounting::Consistency::Checks::C06InactiveAccountLine < Accounting::Consistency::Check
  self.check_id = "C06"
  self.severity = "blocking"
  self.title = "Line on an archived account"

  def call
    Accounting::PostedLine.joins(:account).where(accounting_accounts: { active: false }).group("accounting_accounts.id", "accounting_accounts.code")
                          .pluck(Arel.sql("accounting_accounts.id"), Arel.sql("accounting_accounts.code"), Arel.sql("COUNT(*)")).map do |id, code, count|
      finding(subject: [ "Accounting::Account", id ], message: "#{count} validated #{'line'.pluralize(count)} on the archived account #{code}", count: count)
    end
  end
end

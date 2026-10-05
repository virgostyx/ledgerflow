# F12b: what each company of the group says it holds of another (receivable and payable, sale and purchase), read in ITS OWN books, in SQL, through the partners it
# marked as a company of the group (`intercompany_company_id`). Nothing here eliminates anything: it is the comparison that the reconciliation report shows, and
# that the elimination rules (once validated) use. Each side is read inside its own tenant; the two are only put side by side afterwards.
module Consolidation::Intragroup
  Row = Struct.new(:kind, :creditor_id, :creditor, :debtor_id, :debtor, :heading_creditor, :heading_debtor, :amount_creditor, :amount_debtor, keyword_init: true) do
    def difference = amount_creditor - amount_debtor
    def matched = [ amount_creditor, amount_debtor ].min
    def to_h = super.merge("difference" => difference, "matched" => matched).transform_values { |v| v.is_a?(BigDecimal) ? v.to_s("F") : v }
  end

  # kind "balances": pairs [heading of the creditor (assets), heading of the debtor (liabilities)] at the date;
  # kind "flows": pairs [income heading of the seller, expense heading of the buyer] from the start of the fiscal year of each to the date.
  def self.rows(members, date, kind:, pairs:)
    members.permutation(2).flat_map do |a, b|
      pairs.filter_map do |heading_a, heading_b|
        side_a = statements_of(kind)
        amount_a = amount(a, b, heading_a, side_a.first, date, kind)
        amount_b = amount(b, a, heading_b, side_a.last, date, kind)
        next if amount_a.zero? && amount_b.zero?

        Row.new(kind: kind, creditor_id: a["entity_id"], creditor: a["name"], debtor_id: b["entity_id"], debtor: b["name"], heading_creditor: heading_a, heading_debtor: heading_b,
                amount_creditor: amount_a, amount_debtor: amount_b)
      end
    end
  end

  def self.statements_of(kind) = kind == "balances" ? %w[assets liabilities] : %w[income income]

  # What `member` shows in a heading about the partners that stand for `counterpart`, as a positive amount on the side of the heading.
  def self.amount(member, counterpart, code, statement, date, kind)
    row = Consolidation::Statements.leaf(statement, code) or raise ArgumentError, "#{code} is not a heading of the #{statement} statement that holds accounts"
    ActsAsTenant.with_tenant(Entity.find(member["entity_id"])) do
      partner_ids = Accounting::Partner.where(intercompany_company_id: counterpart["entity_id"]).pluck(:id)
      return BigDecimal("0") if partner_ids.empty?

      lines = Accounting::JournalEntryLine.joins(:journal_entry, :account).where(partner_id: partner_ids)
                .merge(Accounting::JournalEntry.where(status: Accounting::JournalEntry.ledger_status_values))
                .where("accounting_journal_entries.entry_date <= ?", date)
                .merge(Accounting::JournalEntry.where(Accounting::TrialBalanceQuery::NOT_CLOSING, Accounting::JournalEntry::CLOSING_SOURCE, Accounting::JournalEntry::CLOSING_SOURCE))
      lines = lines.where("accounting_journal_entries.entry_date >= ?", Date.parse(member.fetch("fy_start"))) if kind == "flows"
      lines = lines.where(code_condition(row))
      debit, credit = lines.pick(Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.debit), 0)"), Arel.sql("COALESCE(SUM(accounting_journal_entry_lines.credit), 0)"))
      row["side"] == "debit" ? debit - credit : credit - debit
    end
  end

  def self.code_condition(row)
    like = row["prefixes"].map { "accounting_accounts.code LIKE #{Accounting::Account.connection.quote("#{_1}%")}" }.join(" OR ")
    except = Array(row["except"]).map { Accounting::Account.connection.quote(_1) }
    except.any? ? "(#{like}) AND accounting_accounts.code NOT IN (#{except.join(', ')})" : "(#{like})"
  end
  private_class_method :code_condition
end

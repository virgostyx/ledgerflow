# F12b: the statements of the group, worked out from the headings of the annual accounts (R07/R08, config/annual_accounts/company_abridged.yml): the amounts of the
# headings that hold accounts are cumulated and moved by the entries, and every heading that adds others (and the result) is computed again from them, so that
# the consolidated balance sheet is the one of the model, balanced when its entries are.
module Consolidation::Statements
  STATEMENTS = Accounting::AnnualAccounts::STATEMENTS.map(&:to_s).freeze

  def self.definition = @definition ||= YAML.safe_load_file(Accounting::AnnualAccounts::MODEL)

  # The row of a heading that holds accounts, or nil.
  def self.leaf(statement, code) = definition.fetch(statement.to_s).find { |row| row["code"] == code && row["prefixes"] }

  def self.leaf_codes(statement) = definition.fetch(statement.to_s).select { |row| row["prefixes"] }.map { |row| row["code"] }

  # { code => amount } for every heading, from the amount each leaf heading holds of its own (`own`) and what the entries move (`deltas`).
  def self.compute(own:, deltas: {})
    figures = {}
    %w[income assets liabilities].each do |statement|
      definition.fetch(statement).each do |row|
        figures[row["code"]] =
          if row["sum"]
            row["sum"].sum(BigDecimal("0")) { |part| part.start_with?("-") ? -figures.fetch(part.delete_prefix("-")) : figures.fetch(part) }
          else
            (BigDecimal((own[row["code"]] || 0).to_s) + BigDecimal((deltas[row["code"]] || 0).to_s) + Array(row["add"]).sum(BigDecimal("0")) { |code| figures.fetch(code) }).round(2)
          end
      end
    end
    figures
  end

  # What a company holds of its own in each leaf heading: its figure, without the headings its row adds (the result of the year in "14"), so that the
  # result is added once, from the consolidated income statement.
  def self.own_of(figures)
    STATEMENTS.flat_map { |statement| definition.fetch(statement).select { |row| row["prefixes"] } }.to_h do |row|
      [ row["code"], BigDecimal(figures.fetch(row["code"]).to_s) - Array(row["add"]).sum(BigDecimal("0")) { |code| BigDecimal(figures.fetch(code).to_s) } ]
    end
  end

  def self.difference(figures) = figures.fetch("20/58") - figures.fetch("10/49")

  # [{code, label, level, amount}] of a statement, for the screens and the exports.
  def self.rows(statement, figures) = definition.fetch(statement.to_s).map { |row| { "code" => row["code"], "label" => row["label"], "level" => row["level"], "amount" => figures.fetch(row["code"]) } }
end

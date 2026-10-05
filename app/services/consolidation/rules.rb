# F12b: the consolidation rules, and what each one needs to be validated. A rule is NOT applied until an accountant's validation is recorded for the group
# (Consolidation::RuleValidation): the engine reads its parameters from that record, never from here. The `parameters` below are only what the form proposes
# to the person recording the validation (a proposal written by the developer, not a validated choice: see QUESTIONS.md § F12).
module Consolidation::Rules
  DEFINITIONS = {
    "intragroup_balances" => {
      title: "Eliminate intragroup receivables and payables", needed_for: "partners marked as a company of the group, with open balances between two members",
      parameters: { "pairs" => [ %w[40/41 42/48], %w[29 17] ] } # [heading of the creditor company, heading of the debtor company]
    },
    "intragroup_flows" => {
      title: "Eliminate intragroup sales and purchases", needed_for: "partners marked as a company of the group, with sales and purchases between two members",
      parameters: { "pairs" => [ %w[70 61] ] } # [income heading of the seller, expense heading of the buyer]
    },
    "minority_interests" => {
      title: "Minority interests", needed_for: "a fully consolidated member held for less than 100 %",
      parameters: { "equity_heading" => "10/15", "result_heading" => "9904" }
    },
    "equity_method" => {
      title: "Simple equity method", needed_for: "a member consolidated by the equity method",
      parameters: { "participation_heading" => "28", "equity_heading" => "10/15", "result_heading" => "9904" }
    },
    "translation" => {
      title: "Translation of a member that keeps its accounts in a foreign currency", needed_for: "a member whose currency is not the currency of the group",
      parameters: { "balance_rate_type" => "closing", "income_rate_type" => "monthly_average", "difference_heading" => "14" }
    }
  }.freeze

  def self.keys = DEFINITIONS.keys
  def self.fetch(key) = DEFINITIONS.fetch(key.to_s)
end

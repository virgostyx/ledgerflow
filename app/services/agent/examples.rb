# Questions to start from, for the screen the panel was opened on (A05): the empty conversation offers them instead of a blank box.
module Agent::Examples
  GENERIC = [ "What is the balance of account 400000?", "Which customers are more than 60 days late?", "Are there anomalies to fix before the closing?" ].freeze
  BY_SCREEN = {
    %r{reports#aged_balance} => [ "Who owes the most?", "Which of them are more than 90 days late?", "What share of the receivables is overdue?" ],
    %r{reports#unlettered_lines} => [ "Which open lines are the oldest?", "What is still open for our biggest customer?" ],
    %r{reports#(trial_balance|general_ledger)} => [ "Which accounts moved the most this year?", "What is the balance of account 400000?", "Show me the biggest movements of account 604000." ],
    %r{reports#(annual_accounts|balance_sheet|income_statement)} => [ "What is our result so far this year?", "How do revenue and charges compare with last year?" ],
    %r{vat} => [ "What VAT do we have for this quarter?", "Which grids carry the most?" ],
    %r{consistency} => [ "What should I fix first?", "Are there blocking anomalies?" ],
    %r{bank} => [ "Is the bank reconciled?", "What is on the statement and not booked?" ]
  }.freeze

  def self.for(screen) = BY_SCREEN.find { |pattern, _| screen.to_s.match?(pattern) }&.last || GENERIC
end

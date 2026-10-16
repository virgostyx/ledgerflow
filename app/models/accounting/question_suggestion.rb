# B02c: the treatment the firm suggests for a quick answer ("professional: book as an expense"). Shown to the accountant with the answer, as a suggestion: nothing is applied from it.
class Accounting::QuestionSuggestion < ApplicationRecord
  self.table_name = "accounting_question_suggestions"

  acts_as_tenant :entity
end

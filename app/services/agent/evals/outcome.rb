# What happened when a case was played (A12): what the agent answered, which tools it called and with what result, what was sent to the model after masking, what changed in the books, what
# the defences recorded. The checks look at this and nothing else.
module Agent::Evals
  Outcome = Data.define(:text, :status, :flags, :tool_calls, :tool_results, :payload, :books_before, :books_after, :security_kinds, :error, :tokens, :citations, :proposals)
end

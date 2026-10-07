# What comes back from a tool is data, never an instruction (A03). The fields of free text (a label, a description, a document name) and the names of people and companies are the ones a third party wrote: they are scanned
# for what looks like an instruction to an AI, cleaned of hidden and control characters, and cut to 500 characters before the model sees them. The other fields are the
# application's own and are left alone.
module Agent::Untrusted
  MAX_LENGTH = 500
  MAX_LONG_LENGTH = 1200
  THIRD_PARTY = %i[free_text personal].freeze
  HIDDEN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁠-⁩﻿]/

  # => [cleaned copy of the result, findings]; a finding is { patterns:, excerpt: } for one field that looked like an instruction.
  def self.clean(tool, result)
    copy = result.deep_dup
    findings = []
    tool.field_classes.to_h.select { |_, kind| THIRD_PARTY.include?(kind) }.each_key do |path|
      Agent::FieldPath.update(copy, path) do |text|
        next text unless text.is_a?(String)

        patterns = Agent::InjectionDetector.scan(text)
        findings << { patterns: patterns, excerpt: Agent::Security.mask_excerpt(text) } if patterns.any?
        shorten(text.gsub(HIDDEN, ""), tool.long_text.include?(path) ? MAX_LONG_LENGTH : MAX_LENGTH)
      end
    end
    [ copy, findings ]
  end

  def self.shorten(text, limit = MAX_LENGTH) = text.length > limit ? "#{text[0, limit]}…" : text
end

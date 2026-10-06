# What comes back from a tool is data, never an instruction (A03). The fields of free text (a label, a description, a document name) and the names of people and companies are the ones a third party wrote: they are scanned
# for what looks like an instruction to an AI, cleaned of hidden and control characters, and cut to 500 characters before the model sees them. The other fields are the
# application's own and are left alone.
module Agent::Untrusted
  MAX_LENGTH = 500
  THIRD_PARTY = %i[free_text personal].freeze
  HIDDEN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁠-⁩﻿]/

  # => [cleaned copy of the result, findings]; a finding is { patterns:, excerpt: } for one field that looked like an instruction.
  def self.clean(tool, result)
    copy = result.deep_dup
    findings = []
    tool.field_classes.to_h.select { |_, kind| THIRD_PARTY.include?(kind) }.each_key do |path|
      update(copy, path.split(".")) do |text|
        next text unless text.is_a?(String)

        patterns = Agent::InjectionDetector.scan(text)
        findings << { patterns: patterns, excerpt: Agent::Security.mask_excerpt(text) } if patterns.any?
        shorten(text.gsub(HIDDEN, ""))
      end
    end
    [ copy, findings ]
  end

  def self.shorten(text) = text.length > MAX_LENGTH ? "#{text[0, MAX_LENGTH]}…" : text

  # Replaces, by the block's answer, the value at the path: "data.*.label" is the label of every element of the list "data" ("*" stands for each element of a list).
  def self.update(node, path, &block)
    key, *rest = path
    case node
    when Array then node.each { |item| update(item, rest, &block) } if key == "*"
    when Hash
      return unless node.key?(key)

      rest.empty? ? node[key] = yield(node[key]) : update(node[key], rest, &block)
    end
  end
  private_class_method :update
end

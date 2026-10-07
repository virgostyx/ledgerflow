# The sources of an answer (A05). The model writes `[[ref:…]]` where a figure comes from; the application checks each one against the references the tools gave in this answer (or an earlier one of
# the conversation), numbers them, and builds the links itself from the table of Agent::Refs: the model never writes a link. A reference that nobody gave is replaced by "[unverified source]".
module Agent::Citations
  MARKER = /\[\[ref:([\w:.\-|]+)\]\]/
  UNVERIFIED = "[unverified source]".freeze

  # => [the text with the invalid markers replaced, [{ "n", "ref", "label", "computed" }], the invalid references]
  def self.resolve(text, known_refs)
    numbers = {}
    invalid = []
    resolved = text.to_s.gsub(MARKER) do
      ref = Regexp.last_match(1)
      if known_refs.include?(ref) && (Agent::Refs.path(ref) || Agent::Refs.computed?(ref))
        numbers[ref] ||= numbers.size + 1
        "[[ref:#{ref}]]"
      else
        invalid << ref
        UNVERIFIED
      end
    end
    [ resolved, numbers.map { |ref, n| { "n" => n, "ref" => ref, "label" => Agent::Refs.label(ref), "computed" => Agent::Refs.computed?(ref) } }, invalid.uniq ]
  end

  # The sanitized HTML of an answer, with each marker turned into its number: a link to the screen when there is one, a note when it is a calculation.
  def self.render(html, citations)
    by_ref = citations.index_by { |citation| citation["ref"] }
    html.gsub(MARKER) do
      ref = Regexp.last_match(1)
      citation = by_ref[ref]
      next UNVERIFIED unless citation

      label = ERB::Util.html_escape("[#{citation['n']}] #{citation['label']}")
      path = citation["computed"] ? nil : Agent::Refs.path(ref)
      path ? %(<sup><a href="#{ERB::Util.html_escape(path)}" title="#{label}" class="text-indigo-700 hover:underline">[#{citation['n']}]</a></sup>) : %(<sup title="#{label} (calculated)">[#{citation['n']}]</sup>)
    end
  end
end

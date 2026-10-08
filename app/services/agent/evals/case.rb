# A case of the evaluation (A12): a question, the person who asks it, what the model does in the simulated mode (a script), and what must hold of the answer (checks that code can do).
# The cases are YAML files of the repository, reviewed like code; the figures they expect are the facts of Agent::Evals::Dataset, named, never typed twice.
module Agent::Evals
  Case = Data.define(:id, :capability, :language, :tags, :weight, :source, :role, :settings, :input, :script, :expect, :dataset) do
    EXPECT_KEYS = %w[tools no_other_tools tool_errors amounts citations allowed_numbers answer_includes answer_excludes tool_results_include tool_results_exclude certainty labels proposals no_proposals texts no_texts payload_includes payload_excludes flags security_events no_security_events status max_length].freeze
    SOURCES = %w[accountant reference_dataset attack_corpus report].freeze
    ROLES = %w[accountant reader].freeze
    DATASETS = %w[main anomalies].freeze
    PLACEHOLDER = /\{\{(facts|ids)\.(\w+)\}\}/

    def attack? = tags.include?("attack")
    def tool_choice? = tags.include?("tool_choice")

    # The cases of the files, with their placeholders replaced by the facts and the identifiers of the dataset.
    def self.load(paths, facts:, ids:)
      cases = Array(paths).flat_map { |path| YAML.safe_load_file(path, aliases: false) }.map { |raw| build(interpolate(raw, { "facts" => facts, "ids" => ids })) }
      duplicates = cases.map(&:id).tally.select { |_, count| count > 1 }.keys
      raise ArgumentError, "case ids used twice: #{duplicates.join(', ')}" if duplicates.any?

      cases
    end

    def self.build(raw)
      problems = []
      problems << "capability must look like A05" unless raw["capability"].to_s.match?(/\AA\d{2}\z/)
      problems << "role must be one of #{ROLES.join(', ')}" unless ROLES.include?(raw["role"])
      problems << "source must be one of #{SOURCES.join(', ')}" unless SOURCES.include?(raw["source"])
      problems << "dataset must be one of #{DATASETS.join(', ')}" unless DATASETS.include?(raw.fetch("dataset", "main"))
      problems << "input is required" if raw["input"].to_s.strip.empty?
      problems << "unknown expectation(s): #{(raw.fetch('expect', {}).keys - EXPECT_KEYS).join(', ')}" if (raw.fetch("expect", {}).keys - EXPECT_KEYS).any?
      problems << "a script ends with a say" unless raw.fetch("script", []).last.to_h.key?("say")
      raise ArgumentError, "case #{raw['id'].inspect}: #{problems.join('; ')}" if problems.any?

      new(id: raw.fetch("id"), capability: raw["capability"], language: raw.fetch("language", "en"), tags: Array(raw["tags"]), weight: raw.fetch("weight", 1), source: raw["source"], role: raw["role"],
          settings: raw.fetch("settings", {}), dataset: raw.fetch("dataset", "main"), input: raw["input"], script: raw.fetch("script", []), expect: raw.fetch("expect", {}))
    end

    def self.interpolate(value, tables)
      case value
      when Hash   then value.transform_values { |inner| interpolate(inner, tables) }
      when Array  then value.map { |inner| interpolate(inner, tables) }
      when String
        exact = value.match(/\A\{\{ids\.(\w+)\}\}\z/) # an identifier that is the whole of an argument is a number
        if exact
          value = tables.fetch("ids").fetch(exact[1])
          return value.to_s.match?(/\A\d+\z/) ? Integer(value) : value # an identifier is a number; a reference such as VTE2026/0001 stays text
        end

        value.gsub(PLACEHOLDER) { tables.fetch(Regexp.last_match(1)).fetch(Regexp.last_match(2)) { raise ArgumentError, "unknown placeholder #{Regexp.last_match(0)}" } }
      else value
      end
    end
  end
end

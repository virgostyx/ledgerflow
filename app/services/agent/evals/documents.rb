# Runs the reading of the corpus of documents and measures it (A09). In the simulated mode the model is an oracle that reads the labels, so that it is the harness that is measured (grounding, checks, metrics);
# in the real mode it is the real model, on the invented corpus only. => the metrics, and the failures of the gates.
module Agent::Evals
  class Documents
    Report = Struct.new(:metrics, :failures, :mode) do
      def passed? = failures.empty?
    end

    def self.run(count: 100, mode: :simulated, gateway: nil)
      built = Agent::Evals::Dataset.build!
      corpus = Agent::Evals::DocumentCorpus.build(count: count)
      ActsAsTenant.with_tenant(built.entity) do
        Agent::Consent.accept!(built.accountant)
        Agent::Setting.for_current_entity.update!(enabled: true)
        rows = corpus.map do |entry|
          model = gateway || (mode.to_sym == :real ? Agent::ModelGateway.new : oracle(entry))
          Agent::Evals::DocumentMetrics::Row.new(entry, Agent::Documents::Reading.call(text: entry.text, user: built.accountant, gateway: model), nil)
        rescue Agent::Documents::Reading::Error => e
          Agent::Evals::DocumentMetrics::Row.new(entry, nil, e.message)
        end
        metrics = Agent::Evals::DocumentMetrics.compute(rows)
        Report.new(metrics, Agent::Evals::DocumentMetrics.gate_failures(metrics), mode.to_sym)
      end
    end

    # The model of the simulated mode: it answers with the labels, as the document prints them.
    def self.oracle(entry)
      fields = entry.labels.transform_values { |value| { "value" => value, "confidence" => "high", "page" => 1, "excerpt" => value } }
      input = { "document_type" => entry.type, "fields" => fields }
      Agent::FakeGateway.new([ Agent::Response.new(stop_reason: "tool_use", usage: { input_tokens: 0, output_tokens: 0 }, model: "oracle", content: [ { type: "tool_use", id: "t", name: Agent::Documents::Submission::NAME, input: input } ]) ])
    end
  end
end

# A12: what the evaluation of the agent found, run by run and case by case, so that two versions can be compared and a regression is seen. A run is one execution of a set of cases in
# one mode (simulated, or real on demonstration data) against one version of the agent (the manifest hash); a result is one case in it. The cases themselves are files of the
# repository, reviewed like code. Reversible.
class CreateAgentEvals < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_eval_runs do |t|
      t.string   :mode, null: false                                   # simulated | real
      t.string   :scope, null: false, default: "all"                  # all, or a capability such as A05
      t.string   :manifest_hash, null: false
      t.jsonb    :manifest, null: false, default: {}                  # the hash of each component of the version
      t.string   :status, null: false, default: "running"            # running | complete | budget_exceeded | failed
      t.integer  :runs_per_case, null: false, default: 1
      t.integer  :cases_total, null: false, default: 0
      t.integer  :cases_passed, null: false, default: 0
      t.jsonb    :metrics, null: false, default: {}
      t.integer  :input_tokens, null: false, default: 0
      t.integer  :output_tokens, null: false, default: 0
      t.integer  :budget_tokens
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :agent_eval_runs, %i[mode scope started_at]

    create_table :agent_eval_results do |t|
      t.references :run, null: false, foreign_key: { to_table: :agent_eval_runs }
      t.string  :case_id, null: false
      t.string  :capability, null: false
      t.integer :attempt, null: false, default: 1
      t.boolean :passed, null: false
      t.jsonb   :checks, null: false, default: {}                    # each deterministic check: true, or why not
      t.text    :answer
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :duration_ms
      t.timestamps
    end
    add_index :agent_eval_results, %i[run_id case_id]
  end
end

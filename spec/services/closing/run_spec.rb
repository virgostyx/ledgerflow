require "rails_helper"

# F10: the closing run and its steps: opened with its 18 steps, evaluated live, acknowledged, skipped, confirmed.
RSpec.describe "Closing run" do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:state) { { check: :ok, action: :pending } }

  # Four fake steps of the four kinds, so that the framework is tested apart from the real steps.
  let(:fake_steps) do
    outcomes = state
    check  = Class.new(Closing::Step) { self.code = "a_check";  self.title = "A check";  self.kind = :check;  self.blocking = true;  define_method(:evaluate) { Closing::Outcome.new(outcomes[:check], { "n" => 1 }) } }
    action = Class.new(Closing::Step) { self.code = "an_action"; self.title = "An action"; self.kind = :action; self.blocking = true;  define_method(:evaluate) { Closing::Outcome.new(outcomes[:action], {}) } }
    manual = Class.new(Closing::Step) { self.code = "a_manual"; self.title = "A manual step"; self.kind = :manual; self.blocking = false }
    report = Class.new(Closing::Step) { self.code = "a_report"; self.title = "A report"; self.kind = :report; self.blocking = false; define_method(:evaluate) { Closing::Outcome.new(:pending, {}) } }
    [ check, action, manual, report ]
  end

  before { allow(Closing::Registry).to receive(:steps).and_return(fake_steps) }

  def open_run = Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)
  def evaluate(run) = Closing::Evaluate.call(run: run)

  it "has the 18 steps of the spec, in order, with their kind and whether they block" do
    allow(Closing::Registry).to receive(:steps).and_call_original
    expect(Closing::Registry.steps.map { |s| [ s.position, s.code, s.kind, s.blocking ] }).to eq([
      [ 1, "preparation", :action, true ], [ 2, "entries_complete", :check, true ], [ 3, "bank", :check, true ], [ 4, "partners", :check, true ],
      [ 5, "vat", :check, true ], [ 6, "fixed_assets", :action, true ], [ 7, "accruals", :action, true ], [ 8, "stock", :manual, false ],
      [ 9, "provisions", :manual, false ], [ 10, "taxes", :manual, false ], [ 11, "suspense", :check, true ], [ 12, "revaluation", :action, true ],
      [ 13, "consistency", :check, true ], [ 14, "analytical_review", :report, false ], [ 15, "closing_entries", :action, true ],
      [ 16, "carry_forward", :action, true ], [ 17, "lock_and_bundle", :action, true ], [ 18, "approval", :manual, true ]
    ])
  end

  describe "opening" do
    it "makes a run with one step per registered step, pending, in the order of the registry" do
      result = open_run
      expect(result).to be_success, result.message
      run = result[:run]

      expect(run).to have_attributes(status: "draft", opened_by: accountant, fiscal_year: fiscal_year)
      expect(run.steps.map { |s| [ s.position, s.code, s.kind, s.blocking, s.status ] }).to eq([
        [ 1, "a_check", "check", true, "pending" ], [ 2, "an_action", "action", true, "pending" ], [ 3, "a_manual", "manual", false, "pending" ], [ 4, "a_report", "report", false, "pending" ]
      ])
    end

    it "refuses a year that is closed, and a second run while one is under way" do
      first = open_run[:run]
      again = open_run
      expect(again).to be_failure
      expect(again.message).to match(/already/i)
      expect(again[:run]).to eq(first)

      first.update!(status: :closed)
      fiscal_year.update!(status: :closed)
      expect(open_run).to be_failure
    end

    it "is audited" do
      run = open_run[:run]
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::ClosingRun", auditable_id: run.id, action: "create")).to exist
    end
  end

  describe "evaluating" do
    let!(:run) { open_run[:run] }

    it "gives each check and action the state it has now, and moves the run on" do
      evaluate(run)
      expect(run.reload.steps.map(&:status)).to eq(%w[ok pending pending pending])
      expect(run).to be_in_progress
    end

    it "keeps what a check found on the step, to show it" do
      evaluate(run)
      expect(run.steps.first.result).to eq("n" => 1)
    end

    it "runs again, and a check that was blocked is ok once what blocked it is gone" do
      state[:check] = :blocked
      evaluate(run)
      expect(run.steps.first.reload).to be_blocked
      state[:check] = :ok
      evaluate(run)
      expect(run.steps.first.reload).to be_ok
    end

    it "makes an action done once its effect stands" do
      state[:action] = :ok
      evaluate(run)
      expect(run.steps.second.reload).to be_done
    end

    it "is ready when every blocking step is settled; the others may wait" do
      state[:action] = :ok
      evaluate(run)
      expect(run.reload).to be_ready
    end

    it "is not ready while a blocking step is blocked or pending" do
      state[:check] = :blocked
      state[:action] = :ok
      evaluate(run)
      expect(run.reload).to be_in_progress
    end

    it "gives the progress as the share of steps settled" do
      state[:action] = :ok
      evaluate(run)
      expect(run.reload.progress).to eq(50) # the check and the action of four
    end

    it "does not move a closed run" do
      run.update!(status: :closed)
      evaluate(run)
      expect(run.reload).to be_closed
    end
  end

  describe "a warning" do
    let!(:run) { open_run[:run] }

    before do
      state[:check] = :warning
      state[:action] = :ok
      evaluate(run)
    end

    it "does not settle the step until acknowledged, with a comment" do
      expect(run.reload).to be_in_progress
      step = run.steps.first
      expect(Closing::AcknowledgeStep.call(step: step, user: accountant, comment: "")).to be_failure
      expect(Closing::AcknowledgeStep.call(step: step, user: accountant, comment: "Seen with the client")).to be_success

      expect(step.reload).to have_attributes(acknowledged_by: accountant, comment: "Seen with the client")
      evaluate(run)
      expect(run.reload).to be_ready
    end

    it "asks again when what the check finds changes into a block" do
      step = run.steps.first
      Closing::AcknowledgeStep.call(step: step, user: accountant, comment: "Seen")
      state[:check] = :blocked
      evaluate(run)
      expect(step.reload).to be_blocked
      expect(run.reload).to be_in_progress
    end

    it "cannot be acknowledged when the step is not in warning" do
      state[:check] = :ok
      evaluate(run)
      expect(Closing::AcknowledgeStep.call(step: run.steps.first.reload, user: accountant, comment: "x")).to be_failure
    end
  end

  describe "skipping" do
    let!(:run) { open_run[:run] }

    it "is allowed for a step that does not block, with a reason" do
      step = run.steps.find_by(code: "a_manual")
      expect(Closing::SkipStep.call(step: step, user: accountant, reason: "")).to be_failure
      expect(Closing::SkipStep.call(step: step, user: accountant, reason: "No stock")).to be_success
      expect(step.reload).to have_attributes(status: "skipped", comment: "No stock", completed_by: accountant)
      expect(step).to be_settled
    end

    it "is refused for a step that blocks" do
      expect(Closing::SkipStep.call(step: run.steps.find_by(code: "a_check"), user: accountant, reason: "Later")).to be_failure
    end

    it "stays skipped when the run is evaluated again" do
      step = run.steps.find_by(code: "a_manual")
      Closing::SkipStep.call(step: step, user: accountant, reason: "No stock")
      evaluate(run)
      expect(step.reload).to be_skipped
    end
  end

  describe "a manual step" do
    let!(:run) { open_run[:run] }
    let(:step) { run.steps.find_by(code: "a_manual") }

    it "needs the confirmation and the comment of a person" do
      expect(Closing::ConfirmStep.call(step: step, user: accountant, comment: "")).to be_failure
      expect(Closing::ConfirmStep.call(step: step, user: accountant, comment: "Stock variation entered, 1 200 EUR")).to be_success
      expect(step.reload).to have_attributes(status: "done", comment: "Stock variation entered, 1 200 EUR", completed_by: accountant)
    end

    it "stays done when the run is evaluated again" do
      Closing::ConfirmStep.call(step: step, user: accountant, comment: "Done")
      evaluate(run)
      expect(step.reload).to be_done
    end

    it "is refused for a step that is not manual" do
      expect(Closing::ConfirmStep.call(step: run.steps.find_by(code: "a_check"), user: accountant, comment: "x")).to be_failure
    end
  end

  it "is not touched once the run is closed" do
    run = open_run[:run]
    run.update!(status: :closed)
    expect(Closing::SkipStep.call(step: run.steps.find_by(code: "a_manual"), user: accountant, reason: "x")).to be_failure
  end
end

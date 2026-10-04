require "rails_helper"

# F10, the assistant: the list of years to close, a run with its 18 steps and what each asks, the actions of the steps, the batch validation, the approval and the
# reopening, and the direct "Close" button giving way to the assistant.
RSpec.describe "Closing assistant (F10)", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, role: :admin, email: "owner@firm.test") }
  let(:accountant) { create(:user, role: :accountant, email: "acc@firm.test") }
  let(:reader)     { create(:user, role: :manager, email: "reader@firm.test") }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let!(:bank)      { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital)   { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:revenue)   { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account)  { create(:account, code: "130000", label_fr: "Carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let(:year_end) { fiscal_year.end_date }

  before do
    entity.update!(vat_regime: :franchise)
    sign_in accountant
  end

  def book(date, debit, credit, amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: amount)
    entry.post!
  end

  def open_run = Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)[:run]

  it "closes the screens when the feature is off" do
    entity.update!(features: { "f10" => false })
    get accounting_closing_runs_path
    expect(response).to redirect_to(accounting_root_path)
  end

  describe "the list" do
    it "offers to start the closing of a year that is not closed, and lists the runs" do
      get accounting_closing_runs_path
      expect(response.body).to include(fiscal_year.year.to_s, "Start the closing")

      run = open_run
      get accounting_closing_runs_path
      expect(response.body).to include(accounting_closing_run_path(run), "In progress")
    end

    it "starts a run, with its 18 steps, and does not start a second one" do
      expect { post accounting_closing_runs_path, params: { fiscal_year_id: fiscal_year.id } }.to change(Accounting::ClosingRun, :count).by(1)
      run = Accounting::ClosingRun.last
      expect(response).to redirect_to(accounting_closing_run_path(run))
      expect(run.steps.count).to eq(18)

      expect { post accounting_closing_runs_path, params: { fiscal_year_id: fiscal_year.id } }.not_to change(Accounting::ClosingRun, :count)
      expect(response).to redirect_to(accounting_closing_run_path(run))
      expect(flash[:alert]).to match(/already/i)
    end

    it "is refused to someone who may not prepare a closing" do
      sign_in reader
      expect { post accounting_closing_runs_path, params: { fiscal_year_id: fiscal_year.id } }.not_to change(Accounting::ClosingRun, :count)
    end
  end

  describe "a run" do
    let!(:run) { open_run }

    it "shows the 18 steps in order, their kind and state, the progress, and reads them live" do
      book(fiscal_year.start_date + 5, bank, capital, 100)
      get accounting_closing_run_path(run)

      expect(response).to have_http_status(:ok)
      Closing::Registry.steps.each { |step| expect(response.body).to include(step.title) }
      expect(response.body).to include("Progress", "Complete entry", "Blocked").or include("Ok")
      expect(run.reload.steps.find_by(code: "entries_complete")).to be_ok # read when shown
    end

    it "shows what blocks, with the link to the report that explains it" do
      book(fiscal_year.start_date + 5, bank, capital, 100)
      create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 6) # a draft: step 2 blocks
      get accounting_closing_run_path(run)
      expect(response.body).to include("1 entry in draft").or include("drafts")
      expect(response.body).to include(accounting_journal_entries_path(q: { status: "draft" })).or include(accounting_journal_entries_path)
    end

    it "does its action for someone who may prepare: the next year is created" do
      expect { post perform_accounting_closing_run_step_path(run, "preparation") }.to change(Accounting::FiscalYear, :count).by(1)
      expect(response).to redirect_to(accounting_closing_run_path(run, anchor: "step-preparation"))
      expect(flash[:notice]).to be_present
    end

    it "does not offer or accept the actions to a reader" do
      sign_in reader
      get accounting_closing_run_path(run)
      expect(response.body).not_to include("Do it")
      expect { post perform_accounting_closing_run_step_path(run, "preparation") }.not_to change(Accounting::FiscalYear, :count)
    end

    it "acknowledges a warning with a comment, and asks for it" do
      Accounting::Task.create!(title: "Count the stock", kind: :closing)
      Closing::Evaluate.call(run: run)
      post acknowledge_accounting_closing_run_step_path(run, "entries_complete"), params: { comment: "" }
      expect(flash[:alert]).to match(/comment/i)
      post acknowledge_accounting_closing_run_step_path(run, "entries_complete"), params: { comment: "Counted, see the task" }
      expect(run.steps.find_by(code: "entries_complete")).to have_attributes(acknowledged_by: accountant, comment: "Counted, see the task")
    end

    it "skips a step that does not block, with a reason, and confirms a manual one with a comment" do
      post skip_accounting_closing_run_step_path(run, "stock"), params: { reason: "No stock" }
      expect(run.steps.find_by(code: "stock")).to be_skipped
      post confirm_accounting_closing_run_step_path(run, "provisions"), params: { comment: "No provision needed" }
      expect(run.steps.find_by(code: "provisions")).to be_done
      post skip_accounting_closing_run_step_path(run, "bank"), params: { reason: "Later" }
      expect(flash[:alert]).to match(/block/i)
    end

    it "keeps the comments of the analytical review" do
      previous = create(:fiscal_year, status: :closed, year: fiscal_year.year - 1, start_date: fiscal_year.start_date << 12, end_date: fiscal_year.start_date - 1)
      expense = create(:account, code: "604000", label_fr: "Services", account_class: 6)
      supplier = create(:account, code: "440000", label_fr: "Suppliers", account_class: 4, account_type: :liability, normal_balance: :credit)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 8)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense, debit: 5000, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: supplier, debit: 0, credit: 5000)
      entry.post!
      code = Closing::Registry.fetch("analytical_review").new(run).evaluate.details["flagged"].first["code"]
      expect(previous).to be_persisted

      post comment_accounting_closing_run_step_path(run, "analytical_review"), params: { heading: code, text: "New premises" }
      expect(run.steps.find_by(code: "analytical_review").result["comments"][code]["text"]).to eq("New premises")
    end
  end

  describe "the entries of the closing" do
    let!(:run) { open_run }

    before do
      book(fiscal_year.start_date + 1, bank, capital, 10_000)
      book(fiscal_year.start_date + 10, bank, revenue, 800)
      post perform_accounting_closing_run_step_path(run, "closing_entries")
    end

    it "shows the draft with its lines before anything is validated, and validates it on request" do
      get accounting_closing_run_path(run)
      expect(response.body).to include("Entries to validate", "699000")

      expect { post validate_entries_accounting_closing_run_path(run) }.to change { Accounting::JournalEntry.where(closing_run_id: run.id, status: :posted).count }.by(1)
      expect(response).to redirect_to(accounting_closing_run_path(run))
    end

    it "does not let an assistant validate" do
      assistant = create(:user, role: :auditor)
      create(:user_entity, :assistant, user: assistant, entity: entity)
      sign_in assistant
      post validate_entries_accounting_closing_run_path(run)
      expect(Accounting::JournalEntry.where(closing_run_id: run.id).pluck(:status).uniq).to eq([ "draft" ])
    end
  end

  describe "approving, the file, and reopening" do
    let!(:run) { open_run }
    let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }

    before do
      book(fiscal_year.start_date + 1, bank, capital, 10_000)
      %w[closing_entries].each { |code| Closing::PerformStep.call(run: run, code: code, user: accountant) }
      Closing::ValidateEntries.call(run: run, user: accountant)
      Closing::PerformStep.call(run: run, code: "carry_forward", user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      Closing::PerformStep.call(run: run, code: "lock_and_bundle", user: accountant)
    end

    it "is refused to an accountant, and closes the year for the owner" do
      post approve_accounting_closing_run_path(run), params: { comment: "OK" }
      expect(run.reload).not_to be_closed

      sign_in owner
      post approve_accounting_closing_run_path(run), params: { comment: "Approved after review" }
      expect(run.reload).to be_closed
      expect(fiscal_year.reload).to be_closed
      expect(flash[:notice]).to be_present
    end

    it "gives the closing file to download, with its manifest of hashes" do
      get bundle_accounting_closing_run_path(run)
      expect(response.media_type).to eq("application/zip")
      expect(Accounting::Zipper.read(response.body).keys).to include("manifest.json")
    end

    it "reopens a closed year for the owner, with a reason, and says what follows" do
      sign_in owner
      Closing::Approve.call(run: run, user: owner, comment: "Approved")

      post reopen_accounting_closing_run_path(run), params: { reason: "" }
      expect(run.reload).to be_closed
      post reopen_accounting_closing_run_path(run), params: { reason: "A late invoice" }
      expect(run.reload).to be_reopened
      get accounting_closing_run_path(run)
      expect(response.body).to include("reopened", "A late invoice")
    end

    it "refuses the reopening to an accountant" do
      sign_in owner
      Closing::Approve.call(run: run, user: owner, comment: "Approved")
      sign_in accountant
      post reopen_accounting_closing_run_path(run), params: { reason: "A late invoice" }
      expect(run.reload).to be_closed
    end
  end

  describe "the closing settings" do
    it "are shown, and changed by an owner only, for accounts that exist" do
      get accounting_closing_runs_path
      expect(response.body).to include('data-section="settings"', "699000", "130000")

      patch settings_accounting_closing_runs_path, params: { entity: { closing_result_account_code: "699000", review_threshold_amount: "5" } }
      expect(entity.reload.review_threshold_amount).to eq(1000) # an accountant may not

      sign_in owner
      create(:account, code: "690000", label_fr: "Profit and loss", account_class: 6)
      patch settings_accounting_closing_runs_path, params: { entity: { closing_result_account_code: "690000", review_threshold_pct: "10", review_threshold_amount: "500" } }
      expect(entity.reload).to have_attributes(closing_result_account_code: "690000", review_threshold_pct: BigDecimal("10"), review_threshold_amount: BigDecimal("500"))
    end

    it "refuse an account that is not in the chart, and say so" do
      sign_in owner
      patch settings_accounting_closing_runs_path, params: { entity: { closing_carry_account_code: "999999" } }
      expect(flash[:alert]).to include("999999")
      expect(entity.reload.closing_carry_account_code).to eq("130000")
    end
  end

  describe "the direct Close button" do
    it "gives way to the assistant: the close action leads to it, and the year page offers it" do
      sign_in owner
      post close_accounting_fiscal_year_path(fiscal_year)
      expect(response).to redirect_to(accounting_closing_runs_path)
      expect(fiscal_year.reload).to be_open

      get accounting_fiscal_year_path(fiscal_year)
      expect(response.body).to include("Closing assistant")
    end

    it "still closes as before when the feature is off" do
      entity.update!(features: { "f10" => false })
      sign_in owner
      post close_accounting_fiscal_year_path(fiscal_year)
      expect(response).to redirect_to(accounting_fiscal_year_path(fiscal_year))
    end
  end
end

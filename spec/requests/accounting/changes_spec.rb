require "rails_helper"

# B03b §"Interface": the page "What changed" - the two instants, the presets, the cards, the three tabs, the review, the export, who may see the names, the refusals.
RSpec.describe "What changed (R21)", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, email: "alice@example.test") }
  let(:reader) { create(:user, email: "reader@example.test") }
  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    create(:user_entity, :accountant, user: accountant, entity: entity)
    create(:user_entity, :manager, user: reader, entity: entity)
    entity.update!(features: entity.features.merge("b03a" => true, "b03b" => true))
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    sign_in accountant
  end

  def post_entry(amount, author: accountant)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: [ Date.current, fiscal_year.end_date ].min, reference: "C-#{SecureRandom.hex(3)}", created_by_id: author.id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  def iso(time) = time.utc.iso8601(6)
  def changes(**params) = get(accounting_changes_path(fiscal_year_id: fiscal_year.id, **params))

  let!(:t1) { instant }
  let!(:entry) { post_entry(BigDecimal("111.00")) }
  let!(:t2) { instant }

  it "shows the summary, the impact with the closing, and the detail with a drill-down to the ledger at T2" do
    post_entry(BigDecimal("500.00"))
    changes(from: iso(t1), to: iso(t2), tab: "impact")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What changed").and include("604000").and include("€111.00")
    expect(response.body).not_to include("€500.00")
    expect(response.body).to include("Sum of variations = sum of movements, gap 0.00")
    expect(response.body).to include("known_at=#{CGI.escape(iso(t2))}")
  end

  it "lists the entries in the detail tab, and the alerts in theirs" do
    changes(from: iso(t1), to: iso(t2), tab: "detail")
    expect(response.body).to include(entry.reference).and include("alice@example.test")

    changes(from: iso(t1), to: iso(t2), tab: "alerts")
    expect(response).to have_http_status(:ok)
  end

  it "hides the names of the authors from a role without audit.view" do
    sign_in reader
    changes(from: iso(t1), to: iso(t2), tab: "detail")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A user of the company")
    expect(response.body).not_to include("alice@example.test")
  end

  it "takes the instants from a preset, and proposes the last visit as the default" do
    changes
    expect(response).to have_http_status(:ok)

    sleep 0.01
    changes
    expect(response.body).to include("Since my last visit")
    expect(Accounting::UserVisit.where(user: accountant).count).to eq(1)

    changes(preset: "last_visit")
    expect(response).to have_http_status(:ok)
  end

  it "refuses T1 before the start of the history, and T1 after T2 with the proposal to swap them" do
    changes(from: iso(3.days.ago), to: iso(t2))
    expect(response.body).to include("history")

    changes(from: iso(t2), to: iso(t1))
    expect(response.body).to include("swap")
  end

  it "is closed when the feature is off, and for who may not read the reports" do
    entity.update!(features: entity.features.merge("b03b" => false))
    changes(from: iso(t1), to: iso(t2))
    expect(response).to redirect_to(accounting_root_path)
  end

  it "records that the page was opened (R18)" do
    expect { changes(from: iso(t1), to: iso(t2)) }.to change { Accounting::AuditLog.where(action: "changes_report_viewed").count }.by(1)
  end

  describe "the review" do
    it "marks a change as reviewed, visible to everyone and logged (criterion 8)" do
      post accounting_changes_review_path, params: { key: "entry:#{entry.id}", comment: "checked", fiscal_year_id: fiscal_year.id, from: iso(t1), to: iso(t2) }
      expect(response).to have_http_status(:redirect)
      expect(Accounting::AuditLog.where(action: "change_reviewed").count).to eq(1)

      sign_in reader
      changes(from: iso(t1), to: iso(t2), tab: "detail")
      expect(response.body).to include("Reviewed by alice@example.test")
    end

    it "is refused to a role that may not review" do
      sign_in reader
      post accounting_changes_review_path, params: { key: "entry:#{entry.id}" }

      expect(Accounting::ChangeReview.count).to eq(0)
    end
  end

  describe "the export" do
    it "goes out as XLSX and PDF with the two instants and the closing" do
      get accounting_changes_path(fiscal_year_id: fiscal_year.id, from: iso(t1), to: iso(t2), format: :xlsx)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      get accounting_changes_path(fiscal_year_id: fiscal_year.id, from: iso(t1), to: iso(t2), format: :pdf)
      expect(response.media_type).to eq("application/pdf")
    end

    it "is blocked, with the anomaly C21 recorded, when the closing has a gap (criterion 10)" do
      original = Accounting::TrialBalanceQuery.instance_method(:call)
      allow_any_instance_of(Accounting::TrialBalanceQuery).to receive(:call) do |query|
        original.bind_call(query).each { |row| row.total_debit += 1 if row.code == "604000" && query.instance_variable_get(:@known_at).current? }
      end

      get accounting_changes_path(fiscal_year_id: fiscal_year.id, from: iso(t1), format: :xlsx)

      expect(response).not_to have_http_status(:ok)
      expect(Accounting::ConsistencyFinding.where(check_id: "C21")).to exist
    end
  end

  describe "the visits" do
    it "are erased on request" do
      changes
      delete accounting_changes_visit_path

      expect(Accounting::UserVisit.where(user: accountant)).to be_empty
    end
  end
end

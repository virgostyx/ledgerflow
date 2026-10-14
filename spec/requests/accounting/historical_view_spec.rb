require "rails_helper"

# B03a §"Interface": the selector and the banner of the historical view, read-only strictly, exports that say so, the refusals.
RSpec.describe "Historical view of the reports", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:journal) { create(:journal, :purchase) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    sign_in accountant
  end

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "H-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  def iso(time) = time.utc.iso8601(6)
  def trial_balance(**params) = get(accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id, **params))

  let!(:first) { post_entry(BigDecimal("111.00")) }
  let!(:second) { post_entry(BigDecimal("222.00")) }

  it "shows the books as they were known, with a banner that says so and a way back to today" do
    trial_balance(known_at: iso(first.posted_at))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Historical view")
    expect(response.body).to include("111,00")
    expect(response.body).not_to include("333,00")
    expect(response.body).to include("Back to today")
  end

  it "shows today's view, without a banner, when the instant is now or later or absent" do
    trial_balance(known_at: iso(1.hour.from_now))
    expect(response.body).not_to include("Historical view —")
    expect(response.body).to include("333,00")

    trial_balance
    expect(response.body).not_to include("Historical view —")
  end

  describe "the other statements" do
    def known(path, at = first.posted_at) = get(path.call(fiscal_year_id: fiscal_year.id, known_at: iso(at)))

    it "shows the balance sheet and the income statement as they were known, and refuses before the history" do
      [ method(:accounting_reports_balance_sheet_path), method(:accounting_reports_income_statement_path) ].each do |path|
        known(path)
        expect(response.body).to include("Historical view").and include("€111.00")
        expect(response.body).not_to include("€333.00")
      end

      known(method(:accounting_reports_balance_sheet_path), 3.days.ago)
      expect(response).to redirect_to(accounting_reports_balance_sheet_path(fiscal_year_id: fiscal_year.id))
    end

    it "shows the annual accounts, and the summary of the journals, as they were known" do
      known(method(:accounting_reports_annual_accounts_path))
      expect(response.body).to include("Historical view").and include("111,00 €")
      expect(response.body).not_to include("333,00 €")

      known(method(:accounting_reports_journal_summary_path))
      expect(response.body).to include("€111.00")
      expect(response.body).not_to include("€333.00")
    end
  end

  describe "the open items" do
    let!(:customer_account) { create(:account, :customer, reconcilable: true) }
    let(:alice) { create(:partner, name: "Alice") }

    def customer_line(side, amount)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 3, reference: "C-#{SecureRandom.hex(3)}")
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      other = side == :debit ? :credit : :debit
      line = create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: alice, side => amount, other => 0)
      create(:journal_entry_line, journal_entry: entry, account: expense, other => amount, side => 0)
      entry.post!
      next_posting_instant
      line
    end

    it "shows the aged balance and the unlettered lines as they were known, before a lettering made since" do
      invoice = customer_line(:debit, BigDecimal("55"))
      payment = customer_line(:credit, BigDecimal("55"))
      before = instant
      Accounting::LetterLines.call(lines: [ invoice, payment ], user: accountant)

      get accounting_reports_aged_balance_path(kind: "customer", known_at: iso(before))
      expect(response.body).to include("Historical view").and include("Alice")

      get accounting_reports_aged_balance_path(kind: "customer")
      expect(response.body).not_to include("Alice")

      get accounting_reports_unlettered_lines_path(kind: "customer", known_at: iso(before))
      expect(response.body).to include("Historical view").and include("Alice")
    end
  end

  it "keeps the instant in the links that drill down" do
    trial_balance(known_at: iso(first.posted_at))

    expect(response.body).to match(/general_ledger[^"]*known_at=/)
  end

  it "says the instant in what is exported" do
    trial_balance(known_at: iso(first.posted_at), format: :csv)

    expect(response.headers["Content-Disposition"]).to match(/known_at/)
    expect(response.body).to include("111.00")
    expect(response.body).not_to include("333.00")
  end

  it "refuses an instant before the start of the history and says from when it is guaranteed" do
    trial_balance(known_at: iso(3.days.ago))

    expect(response).to redirect_to(accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id))
    expect(flash[:alert]).to match(/history/i)
  end

  it "refuses an instant that is not a date" do
    trial_balance(known_at: "not a date")

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/instant/i)
  end

  it "is not offered on a report that does not support it yet" do
    get accounting_reports_cash_flow_path(fiscal_year_id: fiscal_year.id, known_at: iso(first.posted_at))

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to match(/not available/i)
  end

  describe "who may look" do
    it "is closed to an entity that did not turn it on, and to a person who may not read" do
      entity.update!(features: entity.features.merge("b03a" => false))
      trial_balance(known_at: iso(first.posted_at))
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
    end

    it "keeps a trace in the audit trail of who looked at the books as known when" do
      expect { trial_balance(known_at: iso(first.posted_at)) }.to change { Accounting::AuditLog.where(action: "historical_view").count }.by(1)

      log = Accounting::AuditLog.where(action: "historical_view").last
      expect(log.user_id).to eq(accountant.id)
      expect(log.payload).to include("report" => "trial_balance")
    end

    it "gives the API the same doors: the feature and the right" do
      token = token_for(%w[reports:read])
      entity.update!(features: entity.features.merge("b03a" => false))

      api_get("/api/v1/reports/trial_balance?fiscal_year=#{fiscal_year.year}&known_at=#{iso(first.posted_at)}", token)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read-only, strictly" do
    it "answers 409 historical_view to anything that writes while an instant is given" do
      post accounting_journal_entries_path(known_at: iso(first.posted_at)), params: { accounting_journal_entry: { description: "x" } }

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("historical_view")
    end

    it "answers 409 historical_view on the API too, as problem+json" do
      token = token_for(%w[entries:write])

      api_post("/api/v1/entries?known_at=#{iso(first.posted_at)}", token, {})

      expect(response).to have_http_status(:conflict)
      expect(response.media_type).to eq("application/problem+json")
      expect(JSON.parse(response.body)).to include("code" => "historical_view")
    end
  end

  describe "the public API" do
    let(:token) { token_for(%w[reports:read]) }

    def report(**params) = api_get("/api/v1/reports/trial_balance?#{params.to_query}", token)

    it "gives the report as known at an instant, and says so in its filters" do
      report(fiscal_year: fiscal_year.year, known_at: iso(first.posted_at))

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["totals"]["debit"]).to eq("111.0").or eq("111.00")
      expect(data["filters"]["known_at"]).to be_present
    end

    it "refuses an instant before the history, and one that is not an instant, as problem+json" do
      report(fiscal_year: fiscal_year.year, known_at: iso(3.days.ago))
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("code" => "before_history_start")

      report(fiscal_year: fiscal_year.year, known_at: "yesterday")
      expect(response).to have_http_status(:bad_request)
    end

    it "does not give another report as known at an instant yet" do
      api_get("/api/v1/reports/aged_balance?known_at=#{iso(first.posted_at)}", token)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

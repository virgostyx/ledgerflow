require "rails_helper"

# F10, step 14: the analytical review. R07 and R08 with N-1; each heading that moved by more than 20 % and more than 1 000 EUR carries a comment.
RSpec.describe "Closing: analytical review" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: user)[:run] }
  let(:journal) { create(:journal, :purchase) }
  let!(:previous_year) do
    create(:fiscal_year, status: :closed, year: fiscal_year.year - 1, start_date: fiscal_year.start_date << 12, end_date: fiscal_year.start_date - 1)
  end

  def step = Closing::Registry.fetch("analytical_review").new(run)
  def outcome = step.evaluate

  def spend(amount, year)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: year, entry_date: year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: amount)
    entry.post!
  end

  it "has nothing to comment when no heading moved enough, or there is no previous year" do
    spend(500, previous_year)
    spend(550, fiscal_year)
    expect(outcome).to have_attributes(status: :ok)
    expect(outcome.details["flagged"]).to eq([])
  end

  it "flags a heading that moved by more than 20 % and more than 1 000 EUR, with its two amounts" do
    spend(500, previous_year)
    spend(3000, fiscal_year)
    result = outcome

    expect(result).to have_attributes(status: :pending)
    flagged = result.details["flagged"].find { |f| f["amount"] == "3000.0" }
    expect(flagged).to include("previous" => "500.0", "variation" => "2500.0")
  end

  it "does not flag a move of more than 20 % that is under 1 000 EUR, nor one over 1 000 EUR that is under 20 %" do
    spend(100, previous_year)
    spend(400, fiscal_year)          # +300 %, +300 EUR
    other = create(:account, code: "613000", label_fr: "Insurance", account_class: 6)
    [ [ previous_year, 20_000 ], [ fiscal_year, 22_000 ] ].each do |year, amount| # +10 %, +2 000 EUR
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: year, entry_date: year.start_date + 20)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: other, debit: amount, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: amount)
      entry.post!
    end
    expect(outcome.details["flagged"].map { |f| f["amount"] }).to be_empty
  end

  it "flags a heading that had nothing last year and has more than 1 000 EUR now" do
    spend(5000, fiscal_year)
    expect(outcome).to have_attributes(status: :pending)
  end

  it "follows the thresholds of the entity" do
    spend(500, previous_year)
    spend(900, fiscal_year)
    expect(outcome).to have_attributes(status: :ok)
    entity.update!(review_threshold_amount: 100, review_threshold_pct: 10)
    run.reload
    expect(outcome).to have_attributes(status: :pending)
  end

  it "is ok once each flagged heading has its comment, and keeps the comments from one reading to the next" do
    spend(500, previous_year)
    spend(3000, fiscal_year)
    run
    codes = outcome.details["flagged"].map { |f| f["code"] }

    expect(step.comment(user: user, code: codes.first, text: "")).to be_failure
    codes.each { |code| expect(step.comment(user: user, code: code, text: "New contract in March")).to be_success }

    Closing::Evaluate.call(run: run)
    expect(run.steps.find_by(code: "analytical_review")).to be_ok
    expect(run.steps.find_by(code: "analytical_review").result["comments"].values).to all(include("text" => "New contract in March"))
  end

  it "stays pending while one flagged heading has no comment" do
    spend(500, previous_year)
    spend(3000, fiscal_year)
    codes = outcome.details["flagged"].map { |f| f["code"] }
    expect(codes.size).to be > 1 # the heading and the totals that include it
    step.comment(user: user, code: codes.first, text: "Explained")
    expect(outcome).to have_attributes(status: :pending)
  end

  it "warns that the years are not comparable when they have not the same length" do
    run.fiscal_year.update!(end_date: fiscal_year.start_date + 200)
    expect(outcome.details["comparability"]).to match(/same length/i)
  end
end

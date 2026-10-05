require "rails_helper"

# F12a: what an entity says of its own health, from its own books only.
RSpec.describe Portfolio::Snapshot do
  include_context "with open customer lines"

  let(:user) { create(:user, role: :admin) }

  def snapshot(on: Date.current) = ActsAsTenant.with_tenant(entity) { described_class.call(entity, on: on) }

  it "has nothing to say of an empty entity, and says the year is open" do
    expect(snapshot).to have_attributes(
      taken_on: Date.current, closing_status: "open", closing_year: fiscal_year.year, blocking_count: nil, warning_count: nil, unreconciled_bank_lines: 0, oldest_unreconciled_days: nil,
      peppol_pending: 0, peppol_anomalies: 0, inbox_documents: 0, overdue_tasks: 0, overdue_receivables: 0, last_posted_on: nil, computed_at: be_present
    )
  end

  describe "the closing (F10)" do
    it "follows the run of the year: in progress with its progress, ready, closed" do
      run = Accounting::ClosingRun.create!(fiscal_year: fiscal_year, opened_by: user, status: :in_progress)
      expect(snapshot).to have_attributes(closing_status: "in_progress", closing_progress: be_between(0, 100))
      run.update!(status: :ready)
      expect(snapshot.closing_status).to eq("ready")
      fiscal_year.update!(status: :closed, closed_at: Time.current)
      expect(snapshot).to have_attributes(closing_status: "closed", closing_year: fiscal_year.year)
    end
  end

  describe "the next VAT return" do
    before { entity.update!(vat_regime: :normal, vat_filing_frequency: :monthly) }

    let(:jan_start) { fiscal_year.start_date }

    def declare(from, to, status: :submitted)
      Accounting::VatDeclaration.create!(fiscal_year: fiscal_year, period_start: from, period_end: to, period_type: entity.vat_filing_frequency, status: status)
    end

    it "is due on the 20th of the month after the period, and overdue once that day has passed" do
      travel_to(Date.new(fiscal_year.year, 2, 10)) do
        expect(snapshot).to have_attributes(next_vat_due_on: Date.new(fiscal_year.year, 2, 20), vat_overdue: false) # January is not yet filed
      end
      travel_to(Date.new(fiscal_year.year, 2, 25)) do
        expect(snapshot).to have_attributes(next_vat_due_on: Date.new(fiscal_year.year, 2, 20), vat_overdue: true)
        declare(jan_start, jan_start.end_of_month)
        expect(snapshot).to have_attributes(next_vat_due_on: Date.new(fiscal_year.year, 3, 20), vat_overdue: false) # February is next
      end
    end

    it "counts a draft as not filed, a submitted or accepted one as filed, and follows the quarter for a quarterly entity" do
      entity.update!(vat_filing_frequency: :quarterly)
      travel_to(Date.new(fiscal_year.year, 3, 5)) do
        declare(jan_start, jan_start >> 3, status: :draft)
        expect(snapshot.next_vat_due_on).to eq(Date.new(fiscal_year.year, 4, 20))
      end
    end

    it "has none for an entity under the franchise" do
      entity.update!(vat_regime: :franchise)
      expect(snapshot).to have_attributes(next_vat_due_on: nil, vat_overdue: false)
    end
  end

  it "reads the last run of the consistency checks (R19), and says when nothing ran" do
    expect(snapshot.blocking_count).to be_nil
    Accounting::ConsistencyRun.create!(trigger: "manual", started_at: 2.days.ago, finished_at: 2.days.ago, counts: { "blocking" => 2, "warning" => 3, "acknowledged" => 1 })
    Accounting::ConsistencyRun.create!(trigger: "manual", started_at: 1.hour.ago, finished_at: 1.hour.ago, counts: { "blocking" => 1, "warning" => 4, "acknowledged" => 0 })
    expect(snapshot).to have_attributes(blocking_count: 1, warning_count: 4, consistency_run_at: be_within(1.minute).of(1.hour.ago))
  end

  it "counts the bank lines that wait, and the age of the oldest" do
    account = create(:bank_account)
    create(:bank_transaction, bank_account: account, transaction_date: Date.current - 40)
    create(:bank_transaction, bank_account: account, transaction_date: Date.current - 3)
    create(:bank_transaction, bank_account: account, transaction_date: Date.current - 90, status: :reconciled)
    expect(snapshot).to have_attributes(unreconciled_bank_lines: 2, oldest_unreconciled_days: 40)
  end

  it "counts the Peppol invoices that wait or are in anomaly, the documents in the inbox and the late tasks" do
    Accounting::PeppolMessage.create!(direction: :inbound, document_type: :invoice, status: :received, message_id: "a")
    Accounting::PeppolMessage.create!(direction: :inbound, document_type: :invoice, status: :received, message_id: "b")
    Accounting::PeppolMessage.create!(direction: :inbound, document_type: :invoice, status: :needs_review, message_id: "c")
    Accounting::PeppolMessage.create!(direction: :outbound, document_type: :invoice, status: :failed, message_id: "d")
    Accounting::PeppolMessage.create!(direction: :inbound, document_type: :invoice, status: :processed, message_id: "e")
    create(:document, name: "inbox.pdf")
    create(:document, name: "linked.pdf").update!(status: :linked)
    Accounting::Task.create!(title: "Late", due_on: Date.current - 2)
    Accounting::Task.create!(title: "Late but done", due_on: Date.current - 2, status: :done)
    Accounting::Task.create!(title: "Not yet", due_on: Date.current + 2)

    expect(snapshot).to have_attributes(peppol_pending: 2, peppol_anomalies: 2, inbox_documents: 1, overdue_tasks: 1)
  end

  it "totals what customers owe past the due date (R04), and gives the date of the last validated entry" do
    open_line(amount: 100, days_overdue: 30)
    open_line(partner: bob, amount: 40, days_overdue: 0)

    expect(snapshot).to have_attributes(overdue_receivables: BigDecimal("100"), last_posted_on: Date.current)
  end

  it "is one row a day: the same day again updates it, another day adds one" do
    first = snapshot
    expect { snapshot }.not_to change(DossierHealthSnapshot, :count)
    expect(DossierHealthSnapshot.find(first.id).computed_at).to be >= first.computed_at
    expect { snapshot(on: Date.current + 1) }.to change(DossierHealthSnapshot, :count).by(1)
  end

  it "reads only the books of the entity it is given: every query on the books is scoped to it (criterion 2)" do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { Accounting::Task.create!(title: "Theirs", due_on: Date.current - 9) }
    open_line(amount: 100, days_overdue: 30)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { snapshot }

    book_queries = queries.select { |sql| sql.match?(/FROM "(accounting_[a-z_]+|closing_runs)"/) }
    expect(book_queries).not_to be_empty
    expect(book_queries.reject { |sql| sql.include?("entity_id") }).to eq([]), "a query on the books without the entity"
    expect(snapshot.overdue_tasks).to eq(0)
  end
end

require "rails_helper"

# A08: "Explain" on an anomaly, on the first five, and on the VAT difference; the question is fixed for each kind of object.
RSpec.describe "Explaining an anomaly (A08)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    enable_agent!
    sign_in accountant
  end

  def explain(type, id) = post(agent_conversations_path, params: { screen: "accounting/consistency_runs#index", subject_type: type, subject_id: id, explain: "1" })

  it "asks one fixed question for an anomaly, whatever the button sent" do
    expect { explain("R19", "12") }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), "Explain this anomaly.", "en")
    expect(Agent::Conversation.last.context_ref).to eq("type" => "R19", "id" => "12")
  end

  it "asks to explain the five first open anomalies, in the order to fix them" do
    expect { explain("R19top", "3") }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), "Explain the five first open anomalies, in the order to fix them.", "en")
  end

  it "asks to explain a difference for the VAT consistency panel" do
    expect { explain("I7", "9") }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), "Explain this difference.", "en")
  end

  it "asks what changed between two moments (B03b), the instants read from the shape of the reference only" do
    expect { explain("R21", "1:20261014T060000Z:20261014T180000Z") }.to have_enqueued_job(Agent::AnswerJob)
      .with(an_instance_of(Agent::Conversation), "Explain what changed in the books between 2026-10-14T06:00:00Z and 2026-10-14T18:00:00Z.", "en")
  end

  it "asks what changed since a moment, up to now" do
    expect { explain("R21", "1:20261014T060000Z:now") }.to have_enqueued_job(Agent::AnswerJob)
      .with(an_instance_of(Agent::Conversation), "Explain what changed in the books between 2026-10-14T06:00:00Z and now.", "en")
  end

  it "asks the plain question, never a text of the page, when the reference of a change is not shaped like one" do
    expect { explain("R21", "1:not-a-moment:now") }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), "Explain this figure.", "en")
  end

  it "asks the plain question for a moment that does not exist" do
    expect { explain("R21", "1:20261340T256100Z:now") }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), "Explain this figure.", "en")
  end

  it "asks to explain an entry" do
    expect { explain("entry", "7") }.to have_enqueued_job(Agent::AnswerJob).with(an_instance_of(Agent::Conversation), a_string_starting_with("Explain this entry"), "en")
  end

  it "shows an Explain button on each anomaly of the list and one for the first five" do
    entry = create(:journal_entry, journal: create(:journal, :purchase), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 3, status: :draft, reference: nil, description: "X")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal("10.00"), credit: 0, label: "X")
    create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: BigDecimal("10.00"), label: "X")
    Accounting::PostJournalEntry.call!(entry: entry)
    finding = Accounting::ConsistencyRun.create!(trigger: "spec", started_at: Time.current).findings.create!(entity: entity, check_id: "C04", severity: "warning", fingerprint: "f1", message: "Account 440000 has a debit balance", subject_type: "Accounting::Account", subject_id: account_440.id)

    get accounting_consistency_runs_path

    expect(response.body).to include('name="subject_type" value="R19"', %(name="subject_id" value="#{finding.id}"), 'name="subject_type" value="R19top"', "Explain the first five")
  end

  it "shows no button when there is no anomaly to explain" do
    Accounting::ConsistencyRun.create!(trigger: "spec", started_at: Time.current)

    get accounting_consistency_runs_path

    expect(response.body).not_to include("Explain the first five")
  end
end

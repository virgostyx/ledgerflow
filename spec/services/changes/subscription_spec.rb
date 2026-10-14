require "rails_helper"

# B03b "Revue et suivi": a reviewer or an owner subscribes to the alerts that matter (late entries, changes in a locked period, changes of IBAN) and is told once a day, with
# counts and a link, never with amounts or names.
RSpec.describe "Subscriptions to the alerts of the changes" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:owner) { create(:user, email: "owner@example.test").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:reader) { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(date)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: "N-#{SecureRandom.hex(3)}", created_by_id: owner.id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 10)
    entry.post!
    next_posting_instant
  end

  describe Changes::Subscription do
    it "subscribes a person to some kinds, changes them, and ends when none is left, recording each action" do
      expect(described_class.set(user: owner, kinds: %w[late iban_change])).to be_success
      expect(Accounting::ChangeSubscription.find_by(user: owner).kinds).to eq(%w[late iban_change])

      described_class.set(user: owner, kinds: %w[late])
      expect(Accounting::ChangeSubscription.find_by(user: owner).kinds).to eq(%w[late])

      described_class.set(user: owner, kinds: [])
      expect(Accounting::ChangeSubscription.where(user: owner)).to be_empty
      expect(Accounting::AuditLog.where(action: "change_subscription_changed").count).to eq(3)
    end

    it "keeps only the kinds that can be subscribed to" do
      described_class.set(user: owner, kinds: %w[late nonsense mass_import])

      expect(Accounting::ChangeSubscription.find_by(user: owner).kinds).to eq(%w[late])
    end
  end

  describe Changes::NotifyAlerts do
    before { Accounting::ChangeSubscription.create!(user: owner, kinds: %w[late]) }

    it "tells the subscriber once, with a count and no name or amount, and not again for the same day" do
      post_entry([ Date.current, fiscal_year.end_date ].min - 40)
      post_entry([ Date.current, fiscal_year.end_date ].min - 2)

      expect { described_class.call }.to change { Accounting::Notification.where(user: owner, event: "changes_alerts:#{Date.current}").count }.by(1)
      note = Accounting::Notification.find_by(user: owner, event: "changes_alerts:#{Date.current}")
      expect(note.data["message"]).to include("1 late entry")
      expect(note.data.to_s).not_to include("owner@example.test")
      expect(note.data.to_s).not_to include("10.0")
      expect { described_class.call }.not_to change(Accounting::Notification, :count)
    end

    it "says nothing when nothing is to be reviewed, and leaves the kinds not subscribed to alone" do
      post_entry([ Date.current, fiscal_year.end_date ].min)
      Accounting::AuditLog.record!(auditable: fiscal_year, action: "bank_account_changed", user: owner)

      expect { described_class.call }.not_to change(Accounting::Notification, :count)
    end

    it "remembers when it told, and looks only at what is new" do
      post_entry([ Date.current, fiscal_year.end_date ].min - 40)
      described_class.call
      travel_to(1.day.from_now) { expect { described_class.call }.not_to change(Accounting::Notification, :count) }
      expect(Accounting::ChangeSubscription.find_by(user: owner).last_notified_at).to be_present
    end

    it "does not tell someone who may no longer review the changes" do
      Accounting::ChangeSubscription.create!(user: reader, kinds: %w[late])
      post_entry([ Date.current, fiscal_year.end_date ].min - 40)

      described_class.call

      expect(Accounting::Notification.where(user: reader)).to be_empty
    end

    it "does nothing for a company that did not turn the feature on" do
      entity.update!(features: entity.features.merge("b03b" => false))
      post_entry([ Date.current, fiscal_year.end_date ].min - 40)

      expect { described_class.call }.not_to change(Accounting::Notification, :count)
    end
  end
end

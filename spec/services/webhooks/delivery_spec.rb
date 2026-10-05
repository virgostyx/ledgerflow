require "rails_helper"

# F13c criterion 7 and the cases of §15: a webhook is signed and checkable, a failure is tried again as the policy says, a destination that stays down suspends
# the subscription and tells the owners, and every event of the list is emitted by the thing that happens.
RSpec.describe "Outgoing webhooks" do
  include ActiveJob::TestHelper
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:url)      { "https://hooks.example.com/ledgerflow" }
  let!(:journal) { create(:journal, code: "OD", journal_type: :misc) }
  let!(:owner)   { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }

  def draft_entry(date = fiscal_year.start_date + 1)
    create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date).tap do |entry|
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 10, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 10)
    end
  end

  def perform_enqueued(&) = perform_enqueued_jobs(only: Webhooks::DeliverJob, &)

  describe "delivery (criterion 7)" do
    let(:subscription) { subscribe(url: url) }
    let!(:receiver)    { receiver_at(url, subscription.secret) }

    it "sends the event signed, with its envelope, and the receiver verifies it with the secret" do
      perform_enqueued { Accounting::PostJournalEntry.call!(entry: draft_entry) }

      expect(receiver.deliveries.size).to eq(1)
      delivery = receiver.deliveries.first
      expect(delivery[:body]).to include("event" => "entry.posted", "payload_version" => 1, "entity_id" => entity.id)
      expect(delivery[:body]["id"]).to match(/\A\h{8}-\h{4}-/)
      expect(delivery[:body]["data"]).to include("status" => "posted", "journal" => "OD", "fiscal_year" => fiscal_year.year)
      expect(delivery[:headers]).to include("X-Ledgerflow-Event" => "entry.posted", "User-Agent" => "LedgerFlow-Webhooks/1")
      expect(WebhookDelivery.last).to have_attributes(status: "delivered", attempts: 1, last_response_code: 200, delivered_at: be_present)
      expect(subscription.reload).to have_attributes(consecutive_failures: 0, last_delivery_at: be_present)
    end

    it "is rejected by the receiver when the signature is forged, and is then tried again, not lost" do
      receiver.secret = "whsec_the_wrong_one"
      Accounting::PostJournalEntry.call!(entry: draft_entry)
      Webhooks::Deliver.call(WebhookDelivery.last)

      expect(receiver.rejected.size).to eq(1)
      expect(receiver.deliveries).to be_empty
      expect(WebhookDelivery.last).to have_attributes(status: "pending", attempts: 1, last_response_code: 400, last_error: "HTTP 400")
      expect(WebhookDelivery.last.next_attempt_at).to be_within(5.seconds).of(1.minute.from_now)
    end

    it "carries no more than a receiver needs: identifiers and a summary, no lines, no amounts of the books" do
      perform_enqueued { Accounting::PostJournalEntry.call!(entry: draft_entry) }
      expect(receiver.deliveries.first[:body]["data"].keys).to match_array(%w[id reference status entry_date journal fiscal_year reversal_of_id])
    end
  end

  describe "failures: the policy" do
    let(:subscription) { subscribe(url: url, max_failures: 100) }
    let!(:receiver)    { receiver_at(url, subscription.secret).tap { |r| r.fail_with = 503 } }

    it "tries again at growing intervals, and gives up after the eighth attempt" do
      delivery = Webhooks::Emit.call("period.locked", { id: 1 }).first
      waits = []
      8.times do
        Webhooks::Deliver.call(delivery.reload)
        waits << (delivery.reload.next_attempt_at && (delivery.next_attempt_at - Time.current).round(-1).to_i)
      end

      expect(waits).to eq([ 60, 300, 1800, 7200, 21_600, 43_200, 86_400, nil ])
      expect(delivery.reload).to have_attributes(status: "failed", attempts: 8, last_response_code: 503)
      expect(Webhooks::Deliver.call(delivery)).to have_attributes(attempts: 8) # a delivery given up is left alone
    end

    it "queues the next attempt for its time" do
      delivery = nil
      expect { delivery = Webhooks::Emit.call("period.locked", { id: 1 }).first }.to have_enqueued_job(Webhooks::DeliverJob).with(be_a(Integer))
      expect { Webhooks::DeliverJob.perform_now(delivery.id) }.to have_enqueued_job(Webhooks::DeliverJob).at(a_value_within(5.seconds).of(1.minute.from_now))
    end

    it "sends again after a failure when it comes back up, and counts the failures in a row from zero" do
      delivery = Webhooks::Emit.call("period.locked", { id: 1 }).first
      Webhooks::Deliver.call(delivery)
      expect(subscription.reload.consecutive_failures).to eq(1)
      receiver.fail_with = nil
      Webhooks::Deliver.call(delivery.reload)
      expect(delivery.reload.status).to eq("delivered")
      expect(subscription.reload.consecutive_failures).to eq(0)
    end

    it "counts a timeout or a refused connection as a failed attempt, never as an error of the application" do
      stub_request(:post, url).to_timeout
      delivery = Webhooks::Emit.call("period.locked", { id: 1 }).first
      expect { Webhooks::Deliver.call(delivery) }.not_to raise_error
      expect(delivery.reload).to have_attributes(status: "pending", attempts: 1, last_error: a_string_matching(/Timeout|timed out/i))
    end

    it "never connects to an address that is not public, even when the name resolved to one after the subscription was made" do
      allow(Resolv).to receive(:getaddresses).with("hooks.example.com").and_return([ "10.0.0.8" ])
      delivery = Webhooks::Emit.call("period.locked", { id: 1 }).first
      Webhooks::Deliver.call(delivery)
      expect(delivery.reload.last_error).to match(/refused: .*10\.0\.0\.8/)
      expect(WebMock).not_to have_requested(:post, url)
    end
  end

  describe "a destination that stays down" do
    let(:subscription) { subscribe(url: url, max_failures: 3) }

    before { receiver_at(url, subscription.secret).fail_with = 500 }

    it "suspends the subscription after the number of failures set, tells the owners, and holds what comes after" do
      delivery = Webhooks::Emit.call("period.locked", { id: 1 }).first
      3.times { Webhooks::Deliver.call(delivery.reload) }

      expect(subscription.reload).to be_suspended
      expect(subscription.suspended_reason).to eq("3 failed attempts in a row")
      note = Accounting::Notification.find_by(user: owner)
      expect(note.event).to start_with("webhook_suspended:#{subscription.id}")
      expect(note.data).to include("url" => url)

      expect(Webhooks::Emit.call("period.locked", { id: 2 })).to be_empty # a suspended subscription is not offered new events
      held = WebhookDelivery.create!(webhook_subscription: subscription, event: "period.locked", event_id: "x", payload: {})
      Webhooks::Deliver.call(held)
      expect(held.reload.status).to eq("held")
      expect(WebMock).to have_requested(:post, url).times(3)
    end

    it "is resumed by the owner, and what was held can be sent again by hand" do
      subscription.suspend!("test")
      held = WebhookDelivery.create!(webhook_subscription: subscription, event: "period.locked", event_id: "same", payload: { "id" => "same" }, status: "held")
      subscription.resume!
      expect(subscription).to have_attributes(suspended_at: nil, consecutive_failures: 0)

      copy = nil
      expect { copy = Webhooks::Replay.call(held) }.to have_enqueued_job(Webhooks::DeliverJob).with(be_a(Integer))
      expect(copy).to have_attributes(replay_of: held, event_id: "same", status: "pending", payload: { "id" => "same" })
    end
  end

  describe "the secret" do
    it "is kept encrypted, rotated, and the old one signs too for a day" do
      subscription = subscribe(url: url)
      old = subscription.secret
      expect(WebhookSubscription.connection.select_value("SELECT secret FROM webhook_subscriptions WHERE id = #{subscription.id}")).not_to include(old)

      fresh = subscription.rotate_secret!
      expect(fresh).not_to eq(old)
      expect(subscription.signing_secrets).to eq([ fresh, old ])
      travel(25.hours) { expect(subscription.signing_secrets).to eq([ fresh ]) }
    end

    it "signs a delivery with both secrets right after a rotation, so a receiver on the old one still verifies it" do
      subscription = subscribe(url: url)
      receiver = receiver_at(url, subscription.secret)
      subscription.rotate_secret!
      perform_enqueued { Webhooks::Emit.call("period.locked", { id: 1 }) }
      expect(receiver.deliveries.size).to eq(1) # the receiver still holds the old secret
    end
  end

  describe "the subscription" do
    it "refuses an unknown event, no event, a URL that is not public, and a bad failure limit" do
      expect(WebhookSubscription.new(name: "x", url: url, events: [ "entry.exploded" ], secret: "s")).not_to be_valid
      expect(WebhookSubscription.new(name: "x", url: url, events: [], secret: "s")).not_to be_valid
      expect(WebhookSubscription.new(name: "x", url: "http://hooks.example.com", events: [ "period.locked" ], secret: "s").tap(&:valid?).errors[:url]).to include(/https/)
      expect(WebhookSubscription.new(name: "x", url: url, events: [ "period.locked" ], secret: "s", max_failures: 0)).not_to be_valid
    end

    it "is offered only the events it asked for, and nothing from another entity or with the feature off" do
      subscribe(url: url, events: %w[period.locked])
      other = create(:entity)
      ActsAsTenant.with_tenant(other) { WebhookSubscription.create!(name: "Other", url: url, events: %w[period.locked], secret: "s") }

      expect(Webhooks::Emit.call("document.created", { id: 1 })).to be_empty
      emitted = Webhooks::Emit.call("period.locked", { id: 1 })
      expect(emitted.map { |d| d.webhook_subscription.entity_id }).to eq([ entity.id ])

      entity.update!(features: { "f13" => false })
      expect(Webhooks::Emit.call("period.locked", { id: 1 })).to be_empty
    end

    it "emits nothing for what was rolled back, and sends nothing before the commit" do
      subscribe(url: url)
      receiver_at(url, WebhookSubscription.last.secret)
      expect do
        ApplicationRecord.transaction do
          Accounting::PostJournalEntry.call!(entry: draft_entry)
          raise ActiveRecord::Rollback
        end
      end.not_to change(WebhookDelivery, :count)
    end
  end

  describe "the events" do
    before { subscribe(url: url) }

    def events = WebhookDelivery.order(:id).map(&:event)

    it "entry.posted when an entry is validated, entry.reversed when it is reversed" do
      entry = draft_entry
      Accounting::PostJournalEntry.call!(entry: entry)
      expect(events).to eq(%w[entry.posted])

      Accounting::ReverseJournalEntry.call(entry: entry.reload, reason: "Wrong", user: owner)
      expect(events).to match_array(%w[entry.posted entry.reversed entry.posted reconciliation.created])
      reversed = WebhookDelivery.find_by(event: "entry.reversed")
      expect(reversed.payload["data"]).to include("id" => entry.id, "status" => "reversed")
    end

    it "reconciliation.created when lines are lettered" do
      Accounting::Lettering.create!(account: account_440, code: "AA", lettered_on: Date.current)
      expect(events).to eq(%w[reconciliation.created])
      expect(WebhookDelivery.last.payload["data"]).to include("code" => "AA", "account_id" => account_440.id)
    end

    it "period.locked, document.created, peppol.received (inbound only) and closing.completed" do
      Accounting::PeriodLock.create!(starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date.end_of_month, kind: :accounting, lock_reason: "x", locked_by: owner, locked_at: Time.current)
      create(:document, name: "a.pdf")
      Accounting::PeppolMessage.create!(direction: :inbound, document_type: :invoice, status: :received, message_id: "m-in")
      Accounting::PeppolMessage.create!(direction: :outbound, document_type: :invoice, status: :queued, message_id: "m-out")
      run = Accounting::ClosingRun.create!(fiscal_year: fiscal_year, opened_by: owner)
      run.update!(status: :ready)
      run.update!(status: :closed)

      expect(events).to eq(%w[period.locked document.created peppol.received closing.completed])
      expect(WebhookDelivery.find_by(event: "closing.completed").payload["data"]).to include("id" => run.id, "fiscal_year" => fiscal_year.year)
    end
  end
end

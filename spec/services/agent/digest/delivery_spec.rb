require "rails_helper"

# A10a: the alerts, the delivery, the hour of each person, the job. None of it calls a model; none tells the same thing twice in a day.
RSpec.describe "Delivering the summaries" do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:today) { Date.new(2026, 9, 30) }
  let(:now) { Time.utc(2026, 9, 30, 7, 30) } # 09:30 in Brussels

  before do
    enable_agent!
    allow(Agent::ModelGateway).to receive(:new).and_raise("no model")
    allow(Agent::ModelGateway).to receive(:default).and_raise("no model")
  end

  def blocking(fingerprint = "b1")
    run = Accounting::ConsistencyRun.latest_first.first || Accounting::ConsistencyRun.create!(trigger: "spec", started_at: Time.current)
    run.findings.create!(entity: entity, check_id: "C04", severity: "blocking", fingerprint: fingerprint, message: "Customer ACME SA owes 1210.00", subject_type: "Accounting::Account", subject_id: 1)
  end

  def preference(**attrs) = Agent::DigestPreference.create!({ user: accountant, enabled: true, time_zone: "Europe/Brussels", send_hour: 8 }.merge(attrs))

  describe Agent::DigestPreference do
    it "is due once the hour of the person has come, in their time zone, and not twice on one day" do
      pref = preference(send_hour: 8)

      expect(pref.due?(Time.utc(2026, 9, 30, 5, 59))).to be false # 07:59 in Brussels
      expect(pref.due?(Time.utc(2026, 9, 30, 6, 0))).to be true
      pref.update!(last_built_at: Time.utc(2026, 9, 30, 6, 1))
      expect(pref.due?(Time.utc(2026, 9, 30, 12, 0))).to be false
      expect(pref.due?(Time.utc(2026, 10, 1, 6, 0))).to be true
    end

    it "is due on its weekday only when weekly, and never when off" do
      weekly = preference(frequency: "weekly", weekday: 3) # Wednesday: 30 September 2026 is a Wednesday

      expect(weekly.due?(now)).to be true
      expect(weekly.due?(now + 1.day)).to be false
      expect(weekly.tap { |pref| pref.enabled = false }.due?(now)).to be false
    end

    it "refuses a time zone, an hour or a frequency it does not know" do
      expect(Agent::DigestPreference.new(user: accountant, time_zone: "Mars/Base").tap(&:valid?).errors[:time_zone]).to be_present
      expect(Agent::DigestPreference.new(user: accountant, send_hour: 25).tap(&:valid?).errors[:send_hour]).to be_present
      expect(Agent::DigestPreference.new(user: accountant, frequency: "hourly").tap(&:valid?).errors[:frequency]).to be_present
    end
  end

  describe Agent::Digest::Events do
    it "tells a blocking anomaly once, and not again the same day, as an alert of its own" do
      blocking

      first = described_class.check(user: accountant, entity: entity, today: today)
      second = described_class.check(user: accountant, entity: entity, today: today)

      expect(first.map(&:event_type)).to eq([ "blocking_anomaly" ])
      expect(first.first.kind).to eq("event")
      expect(second).to be_empty
      expect(described_class.check(user: accountant, entity: entity, today: today + 1).map(&:event_type)).to eq([ "blocking_anomaly" ])
    end

    it "tells nothing when nothing is urgent" do
      expect(described_class.check(user: accountant, entity: entity, today: today)).to be_empty
    end

    it "does not move the memory of the morning summary: the next one still says what is new" do
      blocking("b1")
      Agent::Digest::Build.call(user: accountant, entity: entity, today: today)
      blocking("b2")
      described_class.check(user: accountant, entity: entity, today: today)

      expect(Agent::Digest::Build.call(user: accountant, entity: entity, today: today + 1).sections.first["items"].first["text"]).to include("1 new since the last summary")
    end
  end

  describe Agent::Digest::Deliver do
    let(:digest) { blocking && Agent::Digest::Build.call(user: accountant, entity: entity, today: today) }

    it "puts a notification in the bell, once, whatever the number of deliveries" do
      described_class.call(digest)
      described_class.call(digest)

      expect(Accounting::Notification.where(user: accountant, event: "agent_digest:#{digest.id}").count).to eq(1)
    end

    it "sends no e-mail unless the person asked for one" do
      expect { described_class.call(digest) }.not_to have_enqueued_mail(Agent::DigestMailer)

      preference(email: true)
      expect { described_class.call(digest) }.to have_enqueued_mail(Agent::DigestMailer, :summary)
    end

    it "writes an e-mail of counts and links, with no amount and no name" do
      mail = Agent::DigestMailer.summary(digest, details: false)

      expect(mail.to).to eq([ accountant.email ])
      expect(mail.body.to_s).to include("1 blocking", "anomalies", agent_digest_url_for(digest))
      expect(mail.body.to_s).not_to match(/ACME|1210|\d[.,]\d{2}\b/)
    end

    it "adds the details only when the company allows it" do
      Agent::Setting.for_current_entity.update!(digest_email_details: true)
      detail_digest = digest

      expect(Agent::DigestMailer.summary(detail_digest, details: true).body.to_s).to include("Customer ACME SA owes 1210.00")
    end

    def agent_digest_url_for(digest) = Rails.application.routes.url_helpers.agent_digest_url(digest, host: Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost")
  end

  describe Agent::DigestJob do
    it "builds the summary of a person whose hour has come, delivers it, and does not build it again" do
      preference
      blocking

      expect { described_class.perform_now(now) }.to change { Agent::Digest.where(kind: "scheduled").count }.by(1)
      expect { described_class.perform_now(now + 1.hour) }.not_to change { Agent::Digest.where(kind: "scheduled").count }
      expect(Accounting::Notification.where(user: accountant).count).to be >= 1
    end

    it "builds nothing before the hour, nor for a person who turned it off, nor when there is nothing to say" do
      pref = preference(send_hour: 12)
      blocking

      expect { described_class.perform_now(now) }.not_to change { Agent::Digest.where(kind: "scheduled").count }
      pref.update!(send_hour: 8, enabled: false)
      expect { described_class.perform_now(now) }.not_to change(Agent::Digest, :count)
    end

    it "does not make an empty summary and still remembers it looked, so that it does not look every hour" do
      pref = preference

      expect { described_class.perform_now(now) }.not_to change(Agent::Digest, :count)
      expect(pref.reload.last_built_at).to be_present
    end

    it "sends an alert to a person who turned the summary on, once a day, even outside their hour" do
      preference(send_hour: 20)
      blocking

      expect { described_class.perform_now(now) }.to change { Agent::Digest.where(kind: "event").count }.by(1)
      expect { described_class.perform_now(now + 2.hours) }.not_to change { Agent::Digest.where(kind: "event").count }
    end

    it "skips an entity where the assistant is off" do
      preference
      blocking
      Agent::Setting.for_current_entity.update!(enabled: false)

      expect { described_class.perform_now(now) }.not_to change(Agent::Digest, :count)
    end
  end
end

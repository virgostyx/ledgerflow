require "rails_helper"

# B01c §6 "Alertes": a batch said to be loaded in the bank whose debit is not found three open days after its execution date; a debited batch whose payments are not validated
# two days after. Each alert is made once (a task and a warning to the owners), and ends when the cause does.
RSpec.describe Payments::CheckDelays do
  include_context "with submitted batch"

  let(:batch) { submitted_batch(posted) } # execution Wed 14 October 2026
  let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  def tasks = Accounting::Task.where(target: batch)

  before { owner }

  describe "no debit found" do
    it "waits three open days after the execution date, then asks a person to look at the statement, once" do
      batch
      travel_to(Time.zone.local(2026, 10, 19, 8, 0))
      described_class.call  # Monday: 3 open days after Wed 14 is Mon 19 (Thu, Fri, Mon)
      expect(tasks.count).to eq(0)

      travel_to(Time.zone.local(2026, 10, 20, 8, 0))
      2.times { described_class.call }

      expect(tasks.count).to eq(1)
      expect(tasks.first.title).to match(/no debit/i)
      expect(Accounting::Notification.where(user: owner).count).to eq(1)
    end

    it "is not made for a batch that was debited, nor for one that was never said to be loaded" do
      batch
      draft = batch_of(posted(unit_price: 77))
      debit_line(batch.total, description: batch.reference).tap do |line|
        Payments::ConfirmDebit.call(batch: batch, user: exporter, transaction: line, items: batch.items.to_a)
      end

      travel_to(Time.zone.local(2026, 10, 30, 8, 0))
      described_class.call

      expect(Accounting::Task.where(target: [ batch, draft ]).where("title ILIKE ?", "%no debit%")).to be_empty
    end

    it "counts the days the bank profile closes" do
      profile.update!(options: { "closed_days" => [ "2026-10-19" ] })
      batch
      travel_to(Time.zone.local(2026, 10, 20, 8, 0))
      described_class.call

      expect(tasks.count).to eq(0)
    end
  end

  describe "entries not validated" do
    before do
      line = debit_line(batch.total, description: batch.reference)
      Payments::ConfirmDebit.call(batch: batch, user: exporter, transaction: line, items: batch.items.to_a).tap { |r| raise r.message if r.failure? }
    end

    it "asks, once, two days after the debit was confirmed" do
      travel_to(Time.current + 1.day)
      described_class.call
      expect(tasks.count).to eq(0)

      travel_to(Time.current + 3.days)
      2.times { described_class.call }

      expect(tasks.pluck(:title).join).to match(/not validated/i)
      expect(tasks.count).to eq(1)
    end

    it "does not ask once they are validated" do
      Payments::PostBatchPayments.call(batch: batch.reload, user: poster)

      travel_to(Time.current + 5.days)
      described_class.call

      expect(tasks.count).to eq(0)
    end
  end

  it "does nothing for a company without the supplier payments" do
    batch
    entity.update!(features: entity.features.merge("b01b" => false))

    travel_to(Time.zone.local(2026, 11, 30, 8, 0))
      described_class.call

    expect(Accounting::Task.count).to eq(0)
  end
end

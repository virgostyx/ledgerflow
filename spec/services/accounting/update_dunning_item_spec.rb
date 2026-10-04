require "rails_helper"

# F09 step 3: the user ticks, edits or leaves out an item before validating. A level above the one proposed must be confirmed (criterion 2).
RSpec.describe Accounting::UpdateDunningItem do
  include_context "with open customer lines"

  let(:user) { create(:user) }
  let!(:line) { open_line(days_overdue: 50) }
  let(:item) { Accounting::PrepareDunningRun.call(user: user, on: as_of)[:run].items.sole }

  def update(**attrs) = described_class.call(item: item, **attrs)

  it "proposes the first level for a line of 50 days never reminded" do
    expect(item).to have_attributes(level: 1, proposed_level: 1)
  end

  it "edits the recipient, the subject and the body" do
    update(recipient: "billing@example.com", subject: "Hello", body: "Pay please")
    expect(item.reload).to have_attributes(recipient: "billing@example.com", subject: "Hello", body: "Pay please")
  end

  it "leaves an item out, and takes it back" do
    update(excluded: true)
    expect(item.reload).to be_excluded
    update(excluded: false)
    expect(item.reload).not_to be_excluded
  end

  describe "a level above the proposal" do
    it "is kept as a choice that has to be confirmed, and the text and charges follow the level" do
      policy.update!(fee_3: 12)
      update(level: 3)

      expect(item.reload).to have_attributes(level: 3, proposed_level: 1, skip_confirmed: false, fees: BigDecimal("12"), subject: "Mise en demeure")
      expect(item).to be_skips_level
    end

    it "is confirmed explicitly, and only for that level" do
      update(level: 3, skip_confirmed: true)
      expect(item.reload.skip_confirmed).to be(true)
      update(level: 2)
      expect(item.reload.skip_confirmed).to be(false)
    end

    it "is not a skip to go back to the proposed level or below" do
      update(level: 3, skip_confirmed: true)
      update(level: 1)
      expect(item.reload).not_to be_skips_level
    end
  end

  it "keeps a text edited by hand when the level does not change" do
    update(body: "My words")
    update(recipient: "other@example.com")
    expect(item.reload.body).to eq("My words")
  end

  it "refuses an item that has been sent" do
    item.update!(status: :sent)
    result = update(excluded: true)
    expect(result).to be_failure
    expect(item.reload).not_to be_excluded
  end

  it "refuses an e-mail without a valid address" do
    expect(update(recipient: "not an address")).to be_failure
  end

  it "refuses to take back an item that would double another of the same day" do
    update(excluded: true)
    other_run = Accounting::DunningRun.create!(run_on: as_of)
    other = other_run.items.create!(partner: alice, run_on: as_of, level: 1, proposed_level: 1, total: 100, channel: :letter)
    expect(update(excluded: false)).to be_failure
    expect(other).to be_persisted
  end
end

require "rails_helper"

# B03b R21: a reviewer marks a change as reviewed (criterion 8: visible to everyone, logged), and the last visit proposes the T1 of the next one (personal, erasable,
# switched off by the company).
RSpec.describe "Reviews and visits of the changes" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let(:other) { create(:user) }

  describe Changes::Review do
    it "marks a change as reviewed, with who and when, and logs it in the audit trail" do
      result = described_class.call(key: "entry:12", user: user, comment: "checked against the invoice")

      expect(result).to be_success
      review = Accounting::ChangeReview.find_by!(change_key: "entry:12")
      expect(review).to have_attributes(reviewer_id: user.id, comment: "checked against the invoice")
      expect(review.reviewed_at).to be_within(5.seconds).of(Time.current)
      log = Accounting::AuditLog.where(action: "change_reviewed").last
      expect(log).to have_attributes(user_id: user.id, auditable_id: review.id)
      expect(log.payload).to include("change_key" => "entry:12")
    end

    it "does it once: a second review keeps the first and says so" do
      described_class.call(key: "entry:12", user: user)
      again = described_class.call(key: "entry:12", user: other)

      expect(again).to be_failure
      expect(Accounting::ChangeReview.where(change_key: "entry:12").pluck(:reviewer_id)).to eq([ user.id ])
    end

    it "gives the state of a list of changes at once, for everyone of the company" do
      described_class.call(key: "entry:1", user: user)

      expect(described_class.reviewed(%w[entry:1 entry:2]).keys).to eq([ "entry:1" ])
    end
  end

  describe Changes::Visit do
    it "remembers the last visit, one per person and company, and gives it back as the default T1" do
      described_class.record(user)
      first = described_class.last(user)
      sleep 0.01
      described_class.record(user)

      expect(Accounting::UserVisit.where(user: user).count).to eq(1)
      expect(described_class.last(user)).to be > first
    end

    it "gives nothing the first time" do
      expect(described_class.last(user)).to be_nil
    end

    it "is erased on request" do
      described_class.record(user)
      described_class.erase(user)

      expect(described_class.last(user)).to be_nil
    end

    it "records nothing when the company switched it off" do
      entity.update!(track_visits: false)
      described_class.record(user)

      expect(described_class.last(user)).to be_nil
    end
  end
end

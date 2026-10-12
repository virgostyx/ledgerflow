require "rails_helper"

# B01b §5 "Contrôle des coordonnées bancaires": the account a supplier is paid on. Encrypted, valid, and not usable until someone else verified it and the observation is over.
RSpec.describe Accounting::PartnerBankAccount do
  include_context "with entity"

  let(:partner) { create(:partner, :supplier) }
  let(:iban)    { "BE68539007547034" }
  let(:author)  { create(:user) }

  def build(**attrs) = described_class.new({ partner: partner, iban: iban, holder_name: "Acme Ltd", created_by: author, first_seen_at: Time.current, cooling_until: 24.hours.from_now }.merge(attrs))

  it "is unverified when it is made, from a manual entry" do
    account = build.tap(&:save!)

    expect(account).to be_unverified
    expect(account).to be_manual
  end

  describe "the IBAN" do
    it "is checked: shape, length of its country, check digits, and a SEPA country" do
      expect(build(iban: "BE68539007547035")).not_to be_valid # wrong check digits
      expect(build(iban: "BE6853900754703")).not_to be_valid  # too short for Belgium
      expect(build(iban: "")).not_to be_valid
      expect(build(iban: "US64SVBKUS6S3300958879")).not_to be_valid # not a SEPA country
      expect(build(iban: "FR1420041010050500013M02606")).to be_valid
    end

    it "is kept without spaces, in capitals" do
      account = build(iban: "be68 5390 0754 7034").tap(&:save!)

      expect(account.iban).to eq("BE68539007547034")
    end

    it "is encrypted in the database, and found again by its value" do
      account = build.tap(&:save!)

      stored = described_class.connection.select_value("SELECT iban FROM partner_bank_accounts WHERE id = #{account.id}")
      expect(stored).not_to include("5390")
      expect(described_class.find_by(iban: iban)).to eq(account)
    end

    it "is shown masked, for the journals and the lists" do
      expect(build.masked_iban).to eq("BE68 **** **** 7034")
      expect(build(iban: "FR1420041010050500013M02606").masked_iban).to eq("FR14 **** **** **** **** ***2 606")
    end
  end

  describe "who and what" do
    it "needs a holder name, kept as it is on the invoice" do
      expect(build(holder_name: "")).not_to be_valid
      expect(build(holder_name: "ACME Ltd. (Brussels)").tap(&:save!).holder_name).to eq("ACME Ltd. (Brussels)")
    end

    it "does not take the same IBAN twice for a supplier, unless the earlier one was replaced" do
      earlier = build.tap(&:save!)
      expect(build).not_to be_valid

      earlier.update!(status: :superseded)
      expect(build).to be_valid
      expect(build(partner: create(:partner, :supplier))).to be_valid # another supplier may share it (a group account)
    end

    it "remembers the account it replaces" do
      old = build.tap(&:save!)
      fresh = build(iban: "FR1420041010050500013M02606", previous_account: old).tap(&:save!)

      expect(fresh.previous_account).to eq(old)
    end
  end

  describe "usable in a batch" do
    it "needs both: verified, and the observation period over" do
      account = build(cooling_until: 1.hour.from_now).tap(&:save!)
      expect(account).not_to be_usable

      account.update!(status: :verified)
      expect(account).not_to be_usable # still observed

      travel 2.hours
      expect(account).to be_usable

      account.update!(status: :blocked)
      expect(account).not_to be_usable
    end

    it "is not usable once superseded" do
      account = build(cooling_until: 1.hour.ago, status: :verified).tap(&:save!)
      expect(account).to be_usable

      account.update!(status: :superseded)
      expect(account).not_to be_usable
    end
  end
end

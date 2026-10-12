require "rails_helper"

# B01b §5 "Contrôle des coordonnées bancaires": a new or changed IBAN is observed and verified by someone else; nothing a document says changes one; owners are told of a change.
RSpec.describe "Supplier bank accounts: register, verify, block" do
  include_context "with entity"

  let(:partner)    { create(:partner, :supplier, name: "Acme Ltd") }
  let(:owner)      { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)  { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:iban)       { "BE68539007547034" }
  let(:other_iban) { "FR1420041010050500013M02606" }

  def register(user: assistant, iban: self.iban, partner: self.partner, **extra)
    Payments::RegisterBankAccount.call(partner: partner, iban: iban, holder_name: "Acme Ltd", user: user, **extra)
  end

  def verify(account, user: accountant, **extra)
    Payments::VerifyBankAccount.call(account: account, user: user, method: :phone_callback, note: "Called the number of the contract", **extra)
  end

  def audit(action) = Accounting::AuditLog.where(auditable_type: "Accounting::PartnerBankAccount", action: action)

  def told(user) = Accounting::Notification.where(user: user).pluck(:event)

  before { owner; accountant; assistant }

  describe "registering" do
    it "makes an unverified account, observed for the hours the entity asks for, written by the person" do
      entity.update!(iban_cooling_hours: 6)

      result = register
      account = result[:account]

      expect(result).to be_success
      expect(account).to be_unverified
      expect(account).to have_attributes(partner: partner, iban: iban, holder_name: "Acme Ltd", created_by: assistant, source: "manual")
      expect(account.cooling_until).to be_within(5.seconds).of(6.hours.from_now)
      expect(account).not_to be_usable
    end

    it "is 24 hours by default" do
      expect(register[:account].cooling_until).to be_within(5.seconds).of(24.hours.from_now)
    end

    it "is refused for an invalid or an already registered IBAN, with the reason" do
      expect(register(iban: "BE68539007547035")).to be_failure
      register
      expect(register).to be_failure
    end

    it "is refused when the feature is off, and to someone who may not write records" do
      reader = create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) }
      expect(register(user: reader)).to be_failure

      entity.update!(features: entity.features.merge("b01b" => false))
      expect(register).to be_failure
    end

    it "does not tell the owners of a first account, but tells them of a change, and keeps the account it may replace" do
      first = register[:account]
      verify(first)
      expect(told(owner)).to be_empty

      result = register(iban: other_iban)
      change = result[:account]

      expect(change.previous_account).to eq(first)
      expect(first.reload).to be_verified # the known account stays the one in use until the new one is verified
      expect(told(owner).join).to include("bank_account_changed")
      expect(told(owner).join).not_to include(iban)
      expect(audit("bank_account_changed").sole.payload).to include("replaces" => first.id, "iban" => change.masked_iban)
    end

    it "writes the registration in the audit trail with the masked IBAN, and no journal ever carries the full one" do
      register(iban: iban)

      log = audit("bank_account_registered").sole
      expect(log).to have_attributes(user_id: assistant.id)
      expect(log.payload).to include("iban" => "BE68 **** **** 7034", "partner_id" => partner.id, "source" => "manual")
      everything = Accounting::AuditLog.pluck(:payload).to_json
      expect(everything).not_to include(iban)
    end
  end

  describe "verifying" do
    let!(:account) { register[:account] }

    it "needs another person than the one who registered it" do
      result = verify(account, user: accountant)
      expect(result).to be_success

      other = register(iban: other_iban, user: accountant)[:account]
      refused = verify(other, user: accountant)
      expect(refused).to be_failure
      expect(refused[:code]).to eq(:same_person)
      expect(other.reload).to be_unverified
    end

    it "needs the right: an assistant cannot verify, even someone else's entry" do
      result = verify(account, user: assistant)

      expect(result).to be_failure
      expect(result[:code]).to eq(:not_allowed)
    end

    it "records who, when, how and what was said, and a method is needed" do
      expect(Payments::VerifyBankAccount.call(account: account, user: accountant, method: nil, note: "x")[:code]).to eq(:method_required)
      expect(Payments::VerifyBankAccount.call(account: account, user: accountant, method: :carrier_pigeon, note: "x")[:code]).to eq(:method_required)

      verify(account)

      expect(account.reload).to have_attributes(status: "verified", verified_by: accountant, verification_method: "phone_callback", verification_note: "Called the number of the contract")
      expect(account.verified_at).to be_within(5.seconds).of(Time.current)
      expect(audit("bank_account_verified").sole.payload).to include("method" => "phone_callback", "iban" => account.masked_iban)
    end

    it "does not make the account usable before the observation is over" do
      verify(account)
      expect(account.reload).not_to be_usable

      travel 25.hours

      expect(account.reload).to be_usable
    end

    it "replaces the supplier's earlier accounts: they are superseded, with their history kept" do
      first = account.tap { |a| verify(a) }
      second = register(iban: other_iban)[:account]

      verify(second, user: owner)

      expect(first.reload).to be_superseded
      expect(second.reload).to be_verified
      expect(audit("bank_account_superseded").sole.payload).to include("replaced_by" => second.id)
    end

    it "refuses an account that is not waiting for verification" do
      verify(account)

      expect(verify(account, user: owner)[:code]).to eq(:not_unverified)
    end
  end

  describe "blocking" do
    let!(:account) { register[:account].tap { |a| verify(a) } }

    it "needs the right and a reason, and takes the account out of use" do
      expect(Payments::BlockBankAccount.call(account: account, user: assistant, reason: "Returned")[:code]).to eq(:not_allowed)
      expect(Payments::BlockBankAccount.call(account: account, user: accountant, reason: "")[:code]).to eq(:reason_required)

      result = Payments::BlockBankAccount.call(account: account, user: accountant, reason: "Payment returned by the bank")

      expect(result).to be_success
      expect(account.reload).to have_attributes(status: "blocked", blocked_reason: "Payment returned by the bank")
      expect(account).not_to be_usable
      expect(audit("bank_account_blocked").sole.payload).to include("reason" => "Payment returned by the bank")
    end
  end

  describe "the account to pay a supplier on" do
    it "is the verified account, whose observation is over; none otherwise" do
      account = register[:account]
      expect(Accounting::PartnerBankAccount.usable_for(partner)).to be_nil

      verify(account)
      expect(Accounting::PartnerBankAccount.usable_for(partner)).to be_nil # still observed

      travel 25.hours
      expect(Accounting::PartnerBankAccount.usable_for(partner)).to eq(account)
    end
  end

  describe "isolation" do
    it "does not let a person of another company verify, nor see an account here" do
      account = register[:account]
      stranger = ActsAsTenant.with_tenant(create(:entity)) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: ActsAsTenant.current_tenant) } }

      result = verify(account, user: stranger)

      expect(result[:code]).to eq(:not_allowed)
      expect(account.reload).to be_unverified
    end
  end
end

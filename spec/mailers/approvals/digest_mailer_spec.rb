require "rails_helper"

# B01a §4: the daily summary to an approver is counts and a link to the authenticated screen. No amount, no name, and never a button that approves.
RSpec.describe Approvals::DigestMailer do
  include_context "with entity"

  let(:user) { create(:user, email: "alice@firm.test", full_name: "Alice Accountant") }

  let(:mail) { described_class.pending(user: user, entity: entity, count: 3, overdue: 1) }

  it "is addressed to the approver, with the number in the subject" do
    expect(mail.to).to eq([ "alice@firm.test" ])
    expect(mail.subject).to eq("[LedgerFlow] 3 invoices to approve — #{entity.legal_name}")
  end

  it "says how many, how many are late, and links to the screen where they are looked at after signing in" do
    body = mail.text_part&.body&.to_s || mail.body.to_s

    expect(body).to include("3 invoices are waiting for your approval").and include("1 of them is past its due date")
    expect(body).to include("/accounting/approvals")
  end

  it "says it in the singular for one" do
    one = described_class.pending(user: user, entity: entity, count: 1, overdue: 0)

    expect(one.subject).to include("1 invoice to approve")
    expect((one.text_part&.body || one.body).to_s).to include("1 invoice is waiting").and(satisfy { |t| !t.include?("past its due date") })
  end

  it "has nothing that approves: the only link is the screen itself (no token, no decision), and no amount" do
    parts = [ mail.text_part, mail.html_part, (mail unless mail.multipart?) ].compact.map { |part| part.body.to_s }.join("\n")

    expect(parts).not_to match(/€|EUR|\d+[.,]\d{2}\b/) # no amount
    links = parts.scan(%r{https?://[^\s"<>]+})
    expect(links).not_to be_empty
    expect(links).to all(match(%r{\Ahttps?://[^/?#]+/accounting/approvals\z})) # the screen itself: no query, no token, no decision
  end
end

RSpec.describe Approvals::DigestJob do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let!(:policy) do
    Approvals::Policy.create!(name: "all", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin accountant])
    end
  end
  let(:accountant) { create(:user, email: "alice@firm.test").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:owner)      { create(:user, email: "olga@firm.test").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }

  def submit(due: Date.current + 5)
    invoice = create(:invoice, :supplier, fiscal_year: fiscal_year, due_date: due).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "100.00") }
    Approvals::Submit.call(invoice: invoice, user: nil)[:request]
  end

  def mails = ActionMailer::Base.deliveries

  before do
    ActionMailer::Base.deliveries.clear
    accountant
    owner
  end

  it "mails each approver who has something waiting, once a day, with the count and the late ones" do
    submit
    submit(due: Date.current - 2)

    described_class.perform_now

    expect(mails.map(&:to).flatten).to contain_exactly("alice@firm.test", "olga@firm.test")
    expect(mails.first.subject).to include("2 invoices to approve")
    expect((mails.first.text_part || mails.first).body.to_s).to include("1 of them is past its due date")

    expect { described_class.perform_now }.not_to(change { mails.size })
  end

  it "mails again the next day" do
    submit
    described_class.perform_now
    travel 1.day

    expect { described_class.perform_now }.to change { mails.size }.by(2)
  end

  it "does not mail when nothing waits" do
    described_class.perform_now

    expect(mails).to be_empty
  end

  it "does not mail someone who has none waiting, whoever else has" do
    other = Approvals::Policy.create!(name: "elsewhere", subject: :purchase_invoice, priority: 0, conditions: { "min_amount" => "5" })
    other.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ accountant.id ])
    submit

    described_class.perform_now

    expect(mails.map(&:to).flatten).to eq([ "alice@firm.test" ])
  end

  it "leaves out someone who asked for no e-mail" do
    UserEntity.find_by(user: owner, entity: entity).update!(notify_by_email: false)
    submit

    described_class.perform_now

    expect(mails.map(&:to).flatten).to eq([ "alice@firm.test" ])
  end

  it "ignores an entity that has the feature off" do
    submit
    entity.update!(features: entity.features.merge("b01a" => false))

    described_class.perform_now

    expect(mails).to be_empty
  end

  it "is scheduled every morning in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "approvals_digest")

    expect(schedule).to include("class" => "Approvals::DigestJob")
  end
end

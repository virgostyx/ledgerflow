require "rails_helper"

# B01a §4 "Tableau des approbations": mean delays, refusals, requests that are late, by approver and by supplier. The figures of this scenario are worked out by hand.
RSpec.describe Approvals::Dashboard do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:t0)          { Time.zone.local(2026, 10, 12, 9, 0) }
  let(:owner)       { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant)  { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:s1)          { create(:partner, :supplier, name: "Supplier One") }
  let(:s2)          { create(:partner, :supplier, name: "Supplier Two") }

  before do
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin accountant], service_hours: 24)
    owner
    accountant
  end

  def submit(partner, at:, due: Date.new(2026, 11, 30))
    travel_to(at)
    invoice = create(:invoice, :supplier, partner: partner, fiscal_year: fiscal_year, due_date: due).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "100.00") }
    Approvals::Submit.call(invoice: invoice, user: nil)[:request]
  end

  def decide(request, user, kind, at:, **extra)
    travel_to(at)
    Approvals::Decide.call(request: request, user: user, decision: kind, content_fingerprint: request.content_fingerprint, comment: ("because" unless kind == :approved), **extra)
  end

  def dashboard(from: t0 - 30.days, to: nil)
    travel_to(t0 + 10.hours)
    described_class.call(from: from.to_date, to: (to || Time.current).to_date)
  end

  def build_scenario
    r1 = submit(s1, at: t0);               decide(r1, accountant, :approved, at: t0 + 2.hours)
    r2 = submit(s1, at: t0);               decide(r2, owner, :rejected, at: t0 + 4.hours)
    r3 = submit(s2, at: t0);               decide(r3, accountant, :changes_requested, at: t0 + 6.hours)
    r6 = submit(s2, at: t0);               decide(r6, owner, :transferred, at: t0 + 1.hour, transfer_to_id: accountant.id)
    decide(r6, accountant, :approved, at: t0 + 3.hours)
    r4 = submit(s2, at: t0 - 2.days, due: Date.new(2026, 10, 11)) # still waiting, long past its service time, and its invoice is past due
    old = submit(s1, at: t0 - 60.days);    decide(old, accountant, :approved, at: t0 - 60.days + 1.hour) # outside the period
    [ r1, r2, r3, r4, r6, old ]
  end

  it "counts the requests of the period by where they ended up, and what is waiting now" do
    build_scenario

    result = dashboard

    expect(result.submitted).to eq(5)
    expect(result.by_status).to include("approved" => 2, "rejected" => 1, "changes_requested" => 1, "pending" => 1)
    expect(result.pending_now).to eq(1)
  end

  it "gives the refusal rate among the requests decided, the mean time to an approval, and the late ones" do
    build_scenario

    result = dashboard

    expect(result.refusal_rate).to eq(BigDecimal("0.5")) # 2 refused or sent back, out of 4 decided
    expect(result.mean_hours_to_approval).to eq(BigDecimal("2.5")) # 2 h and 3 h
    expect(result.late_by_service_time).to eq(1)
    expect(result.late_by_due_date).to eq(1)
  end

  it "has no rate and no mean when nothing was decided" do
    result = dashboard

    expect(result.submitted).to eq(0)
    expect(result.refusal_rate).to be_nil
    expect(result.mean_hours_to_approval).to be_nil
  end

  it "tells each approver's decisions and how long they took since the request last moved" do
    build_scenario

    rows = dashboard.by_approver.index_by { |row| row.user.full_name }

    expect(rows["Alice Accountant"]).to have_attributes(decisions: 3, approved: 2, rejected: 0, changes_requested: 1, transferred: 0, mean_hours: BigDecimal("3.33"), waiting_now: 1)
    expect(rows["Olga Owner"]).to have_attributes(decisions: 2, approved: 0, rejected: 1, changes_requested: 0, transferred: 1, mean_hours: BigDecimal("2.5"), waiting_now: 1)
  end

  it "tells each supplier's requests, refusals and mean time to an approval" do
    build_scenario

    rows = dashboard.by_supplier.index_by { |row| row.partner.name }

    expect(rows["Supplier One"]).to have_attributes(requests: 2, approved: 1, refused: 1, pending: 0, mean_hours_to_approval: BigDecimal("2.0"))
    expect(rows["Supplier Two"]).to have_attributes(requests: 3, approved: 1, refused: 1, pending: 1, mean_hours_to_approval: BigDecimal("3.0"))
  end

  it "leaves out a decision outside the period, and a request submitted outside it" do
    build_scenario

    result = dashboard(from: t0 - 1.day)

    expect(result.submitted).to eq(4) # r4 (two days back) and the old one are out
    expect(result.by_approver.sum(&:decisions)).to eq(5)
  end

  it "never counts what belongs to another entity" do
    build_scenario
    other = create(:entity)
    ActsAsTenant.with_tenant(other) do
      policy = Approvals::Policy.create!(name: "x", subject: :purchase_invoice, priority: 1)
      policy.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
      invoice = create(:invoice, :supplier, fiscal_year: create(:fiscal_year, status: :open)).tap { |i| create(:invoice_line, invoice: i, account: create(:account), unit_price: "10.00") }
      Approvals::Submit.call(invoice: invoice, user: nil)
    end

    expect(dashboard.submitted).to eq(5)
  end
end

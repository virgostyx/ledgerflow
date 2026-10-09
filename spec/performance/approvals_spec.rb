require "rails_helper"
require "benchmark"

# B01a §13 performance: "À approuver" with 500 items in under 500 ms, and no query per row (the queries do not grow with the list).
RSpec.describe "Performance — approvals", type: :model do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:owner)       { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:account)     { create(:account) }

  before do
    Approvals::Policy.create!(name: "all", subject: :purchase_invoice, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin accountant])
    owner
  end

  # n pending requests spread over 40 suppliers, made with bulk inserts: the point is to measure the screen, not the factories.
  def pending_requests(n)
    now = Time.current
    partners = create_list(:partner, 40)
    invoices = Accounting::Invoice.insert_all!(Array.new(n) { |i|
      { entity_id: entity.id, invoice_type: 1, status: 1, invoice_number: "ACH#{SecureRandom.hex(4)}-#{i}", invoice_date: Date.current - 20, due_date: Date.current + (i % 30), currency: "EUR",
        partner_id: partners[i % 40].id, fiscal_year_id: fiscal_year.id, payment_status: 1, created_at: now, updated_at: now }
    }, returning: %w[id]).rows.flatten
    Accounting::InvoiceLine.insert_all!(invoices.map { |id|
      { entity_id: entity.id, invoice_id: id, account_id: account.id, description: "Services", quantity: 1, unit_price: 100, vat_rate: 21, subtotal_excl_vat: 100, vat_amount: 21,
        total_incl_vat: 121, position: 1, created_at: now, updated_at: now }
    })
    policy = Approvals::Policy.first
    Approvals::Request.insert_all!(invoices.map { |id|
      { entity_id: entity.id, policy_id: policy.id, policy_version: 1, subject_type: "Accounting::Invoice", subject_id: id, current_step: 1, status: 0,
        content_fingerprint: Digest::SHA256.hexdigest(id.to_s), submitted_at: now, step_started_at: now, created_at: now, updated_at: now }
    })
  end

  def count_queries
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  it "lists 500 requests in under 500 ms" do
    pending_requests(500)
    Approvals::Inbox.for(owner) # warm up

    elapsed = Benchmark.realtime { expect(Approvals::Inbox.for(owner).size).to eq(500) }

    puts "  inbox of 500: #{(elapsed * 1000).round} ms"
    expect(elapsed).to be < 0.5
  end

  it "does not ask the database once per row: 10 times the rows, about the same queries" do
    pending_requests(20)
    few = count_queries { Approvals::Inbox.for(owner) }
    pending_requests(180)
    many = count_queries { Approvals::Inbox.for(owner) }

    puts "  queries: #{few} for 20, #{many} for 200"
    expect(many).to be <= few + 10
  end

  it "counts what waits for the menu without a query per row either" do
    pending_requests(200)

    queries = count_queries { Approvals::Inbox.count(owner) }

    puts "  menu count for 200: #{queries} queries"
    expect(queries).to be < 40
  end
end

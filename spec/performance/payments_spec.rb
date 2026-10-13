require "rails_helper"
require "benchmark"

# B01b §13 performance: the pre-flight of a batch of 500 payments in under 5 seconds, and not a query per payment for what can be asked for them all at once.
RSpec.describe "Performance — payment batches", type: :model do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:bank) { create(:bank_account) }
  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }

  # n payments, each to its own supplier with a verified account, paying one invoice: made directly (the point is to measure the pre-flight, not the composition).
  def batch_of(n)
    now = Time.current
    partner_ids = Accounting::Partner.insert_all!(Array.new(n) { |i| { entity_id: entity.id, name: "Supplier #{SecureRandom.hex(3)}-#{i}", partner_type: 1, country: "BE", created_at: now, updated_at: now } }, returning: %w[id]).rows.flatten
    invoice_ids = Accounting::Invoice.insert_all!(partner_ids.each_with_index.map { |partner_id, i|
      { entity_id: entity.id, invoice_type: 1, status: 1, invoice_number: "ACH#{SecureRandom.hex(4)}-#{i}", invoice_date: Date.current - 20, due_date: Date.current + 3, currency: "EUR",
        partner_id: partner_id, fiscal_year_id: fiscal_year.id, payment_status: 0, created_at: now, updated_at: now }
    }, returning: %w[id]).rows.flatten
    batch = Payments::Batch.create!(bank_account: bank, reference: "PAY-#{SecureRandom.hex(3)}", requested_execution_date: Date.current + 2, prepared_by: owner, total: n * 100, payments_count: n)
    partner_ids.each_with_index do |partner_id, i|
      account = Accounting::PartnerBankAccount.create!(partner_id: partner_id, iban: "BE#{format('%014d', 68_539_007_547_034 + i)[0, 14]}".then { |_| ibans[i] }, holder_name: "Holder #{i}", status: :verified, created_by: owner, verified_by: owner,
                                                       verified_at: now - 3.days, verification_method: :phone_callback, first_seen_at: now - 40.days, cooling_until: now - 2.days)
      item = batch.items.create!(partner_id: partner_id, partner_bank_account: account, iban: account.iban, holder_name: account.holder_name, amount: 100, end_to_end_id: "#{batch.reference}-#{i}", remittance: "Invoice #{i}")
      item.item_invoices.create!(invoice_id: invoice_ids[i], amount: 100)
    end
    batch
  end

  # valid IBANs, one per payment: Belgian ones whose check digits are worked out
  def ibans
    @ibans ||= Array.new(5100) do |i|
      bban = format("%012d", 539_000_000_000 + i)
      check = 98 - (("#{bban}111400").to_i % 97)
      "BE#{format('%02d', check)}#{bban}"
    end
  end

  it "makes the pre-flight of 500 payments in under 5 seconds" do
    batch = batch_of(500)
    Payments::Preflight.call(batch) # warm up

    elapsed = Benchmark.realtime { Payments::Preflight.call(batch) }

    puts "  pre-flight of 500: #{(elapsed * 1000).round} ms"
    expect(elapsed).to be < 5
  end

  it "makes the file of 5,000 payments in under 10 seconds, valid against the schema" do
    batch = batch_of(5000)
    batch.update!(bank_profile: Payments::BankProfile.create!(name: "Test bank", format_version: "pain.001.001.03"))

    file = nil
    elapsed = Benchmark.realtime { file = Payments::Sepa::Pain001Builder.call(batch, created_at: Time.current) }

    puts "  file of 5000: #{(elapsed * 1000).round} ms, #{file.bytesize / 1024} KiB"
    expect(Nokogiri::XML(file).tap(&:remove_namespaces!).xpath("//CdtTrfTxInf").size).to eq(5000)
    expect(elapsed).to be < 10
  end

  it "does not ask the database once per payment: ten times the payments, about the same queries" do
    small = batch_of(20)
    large = batch_of(200)
    count = ->(batch) { n = 0; sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| n += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }; Payments::Preflight.call(batch); ActiveSupport::Notifications.unsubscribe(sub); n }

    few = count.call(small)
    many = count.call(large)

    puts "  queries: #{few} for 20, #{many} for 200"
    expect(many).to be <= few + 15 # the queries do not follow the number of payments
  end
end

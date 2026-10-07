# A second invented entity for the evaluation (A08): its books hold anomalies put there on purpose, each with a cause that is known because it was built, so that what the agent finds can be compared with it.
# It is kept apart from the first entity because every figure of the first one is a fact the cases of the other capabilities rely on. Nothing here is real data.
#   C04 inverted balance   a refund of 2000.00 booked on the suppliers account (440000), more than the 1210.00 of invoices: a debit balance of 790.00
#   C05 probable duplicate two supplier invoices with the same reference SUP-1, same date and total (605.00)
#   C06 archived account   a line of 40.00 on 613000, archived after the entry
#   C09 base x rate        invoice ACH2026/0001 whose VAT was changed by hand to 108.00 (base x rate gives 105.00)
#   C12 date gap           invoice VTE2026/0001 dated 2026-03-01 and booked 2026-08-01
#   C14 customer VAT       Acme SA, 1000.00 of sales, no VAT number
#   C03 numbering gap      journal OD: number 12 is missing (an entry deleted outside the application)
#   I6  balance sheet      account 799999 holds 30.00 and belongs to no rubric: assets - liabilities = 30.00
#   C12 is acknowledged, with the comment above
#   a variation            account 611000: 100.00 a month in the first quarter; in the second, the same plus a single line of 4000.00 in June
class Agent::Evals::AnomalyDataset
  ENTITY_NAME = "Agent Evaluation Anomalies".freeze

  ACKNOWLEDGEMENT = "The customer confirmed the sale in August".freeze
  CHECKS = { "finding_c03" => "C03", "finding_c04" => "C04", "finding_c05" => "C05", "finding_c06" => "C06", "finding_c09" => "C09", "finding_c12" => "C12", "finding_c14" => "C14" }.freeze

  def self.facts
    refund, invoices, net = BigDecimal("2000.00"), BigDecimal("605.00") * 2, nil
    net = refund - invoices
    {
      "an_refund" => refund, "an_supplier_invoices" => invoices, "an_c04_balance" => net, "an_duplicate_total" => BigDecimal("605.00"), "an_c09_booked" => BigDecimal("108.00"), "an_c09_expected" => BigDecimal("105.00"), "an_c09_difference" => BigDecimal("3.00"),
      "an_archived_line" => BigDecimal("40.00"), "an_unmapped_balance" => BigDecimal("30.00"), "an_acme_net" => BigDecimal("1000.00"),
      "an_missing_number" => 12, "an_first_quarter" => BigDecimal("300.00"), "an_second_quarter" => BigDecimal("4300.00"), "an_cost_change" => BigDecimal("4000.00"), "an_oneoff" => BigDecimal("4000.00")
    }.transform_values { |value| value.is_a?(Integer) ? value.to_s : Agent::ToolResult.money(value) }
  end

  # The ids of what the run of the consistency checks found: one anomaly per kind, by check.
  def self.ids(entity)
    ActsAsTenant.with_tenant(entity) do
      run = Accounting::ConsistencyRun.order(:id).last
      found = CHECKS.transform_values { |check| run.findings.find_by!(check_id: check).id.to_s }
      found.merge("finding_i6" => run.findings.where(check_id: "C11").find { |finding| finding.data["invariant"] == "I6" }.id.to_s, "an_run" => run.id.to_s, "an_entity" => entity.id.to_s)
    end
  end

  def self.build!(accountant:, reader:)
    existing = ActsAsTenant.without_tenant { Entity.find_by(name: ENTITY_NAME) }
    existing || ActsAsTenant.without_tenant { new(accountant, reader).build }
  end

  def initialize(accountant, reader)
    @accountant, @reader = accountant, reader
  end

  def build
    entity = nil
    ApplicationRecord.transaction do
      entity = Entity.create!(name: ENTITY_NAME, legal_name: ENTITY_NAME, legal_form: "SRL", country: "BE", active: true, created_by: @accountant, features: Entity::FEATURES.index_with { true })
      UserEntity.create!(user: @accountant, entity: entity, role: :accountant)
      UserEntity.create!(user: @reader, entity: entity, role: :manager)
      ActsAsTenant.with_tenant(entity) { fill(entity) }
    end
    entity
  end

  private

  def fill(entity)
    Seeders::PcmnSeeder.call(entity: entity)
    Seeders::JournalsSeeder.call
    @year = Accounting::FiscalYear.create!(year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open)
    @acme = partner("Acme SA", :customer)
    @delta = partner("Delta SPRL", :supplier)
    @entity = entity
    sale = invoice(:customer, "700000", @acme, "2026-03-01", "1000.00")
    first = invoice(:supplier, "600000", @delta, "2026-03-05", "500.00", "SUP-1")
    invoice(:supplier, "600000", @delta, "2026-03-05", "500.00", "SUP-1")
    sale.journal_entry.update_columns(entry_date: Date.new(2026, 8, 1))
    first.update_columns(vat_amount: first.vat_amount + 3)
    costs
    manual("2026-04-01", "2000.00", "440000", "570000", @delta)
    manual("2026-04-02", "40.00", "613000", "570000")
    Accounting::Account.find_by!(code: "613000").update_columns(active: false)
    Accounting::Account.create!(code: "799999", label_fr: "Unmapped evaluation account", account_class: 7, account_type: :revenue, normal_balance: :credit)
    manual("2026-04-03", "30.00", "570000", "799999")
    gap = [ manual("2026-05-01", "10.00", "570000", "700000"), manual("2026-05-02", "11.00", "570000", "700000"), manual("2026-05-03", "12.00", "570000", "700000") ]
    Accounting::JournalEntryLine.where(journal_entry_id: gap[1].id).delete_all
    Accounting::JournalEntry.where(id: gap[1].id).delete_all
    run = Accounting::Consistency::Runner.call(trigger: "evaluation", fiscal_year: @year)
    late = run.findings.find_by!(check_id: "C12")
    Accounting::ConsistencyAcknowledgement.create!(fingerprint: late.fingerprint, comment: ACKNOWLEDGEMENT, user: @accountant, acknowledged_at: Time.current)
  end

  def partner(name, type) = Accounting::Partner.create!(name: name, partner_type: type, is_natural_person: false, city: "Namur", country: "BE", active: true)

  def invoice(type, account_code, partner, date, net, external_ref = nil)
    invoice = Accounting::Invoice.create!(entity: @entity, partner: partner, fiscal_year: @year, invoice_type: type, invoice_date: Date.iso8601(date), due_date: Date.iso8601(date) + 30, status: :draft, currency: "EUR",
                                          vat_treatment: :domestic, external_ref: external_ref)
    Accounting::InvoiceLine.create!(entity: @entity, invoice: invoice, account: Accounting::Account.find_by!(code: account_code), description: "Evaluation #{type} invoice", quantity: 1, unit_price: BigDecimal(net),
                                    vat_rate: BigDecimal("21"), position: 1)
    result = Accounting::PostInvoice.call(invoice: invoice)
    raise "the anomaly dataset could not post an invoice: #{result.message}" if result.failure?

    invoice.reload
  end

  # 100.00 a month on 611000 in the first quarter and the same in the second, plus one line of 4000.00 in June.
  def costs
    %w[01 02 03 04 05 06].each { |month| manual("2026-#{month}-10", "100.00", "611000", "570000") }
    manual("2026-06-20", "4000.00", "611000", "570000")
  end

  def manual(date, amount, debit, credit, partner = nil)
    entry = Accounting::JournalEntry.create!(journal: Accounting::Journal.find_by!(code: "OD"), fiscal_year: @year, entry_date: Date.iso8601(date), description: "Evaluation entry", status: :draft)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry.lines.create!(account: Accounting::Account.find_by!(code: debit), label: "Evaluation", debit: BigDecimal(amount), partner: (partner if debit.start_with?("44")))
    entry.lines.create!(account: Accounting::Account.find_by!(code: credit), label: "Evaluation", credit: BigDecimal(amount), partner: (partner if credit.start_with?("44")))
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end
end

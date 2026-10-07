# The books the evaluation of the agent asks its questions about (A12): a small, invented entity with a handful of invoices on fixed dates, so that what is true of it is known by
# arithmetic on the table below and not by asking the reports. The expected figures of the cases (`facts`) are computed from this table, in plain Ruby, independently of the code
# that is tested: if a report disagreed with them, it is the report that would be wrong, and the dataset spec says so. Nothing here is real data.
module Agent::Evals
  class Dataset
    ENTITY_NAME = "Agent Evaluation Demo".freeze
    AS_OF = Date.new(2026, 9, 30)
    VAT_RATE = BigDecimal("0.21")
    EMAILS = { accountant: "eval-accountant@ledgerflow.test", reader: "eval-reader@ledgerflow.test" }.freeze

    # key => [name, type, natural person?, city]
    PARTNERS = {
      acme: [ "Acme SA", :customer, false, "Bruxelles" ], bravo: [ "Bravo SRL", :customer, false, "Liège" ], charlie: [ "Charlie Dupont", :customer, true, "Namur" ],
      delta: [ "Delta SPRL", :supplier, false, "Gand" ], echo: [ "Echo NV", :supplier, false, "Anvers" ]
    }.freeze

    SALES = [
      { partner: :acme,    date: "2026-06-15", due: "2026-07-15", net: "1000.00" },
      { partner: :acme,    date: "2026-08-20", due: "2026-09-19", net: "500.00" },
      { partner: :bravo,   date: "2026-09-10", due: "2026-10-10", net: "2000.00" },
      { partner: :charlie, date: "2026-03-01", due: "2026-03-31", net: "300.00" }
    ].freeze
    PURCHASES = [
      { partner: :delta, date: "2026-05-05", due: "2026-06-04", net: "1500.00" },
      { partner: :echo,  date: "2026-09-01", due: "2026-10-01", net: "800.00" }
    ].freeze

    Built = Data.define(:entity, :accountant, :reader)

    # What is true of the books above, by arithmetic: every figure as the two-decimal string a tool gives.
    def self.facts
      sales, purchases = SALES.map { |row| row.merge(vat: vat(row[:net])) }, PURCHASES.map { |row| row.merge(vat: vat(row[:net])) }
      gross = ->(row) { BigDecimal(row[:net]) + row[:vat] }
      overdue = ->(rows) { rows.select { |row| Date.iso8601(row[:due]) < AS_OF } }
      older_than = ->(rows, days) { rows.select { |row| (AS_OF - Date.iso8601(row[:due])).to_i > days } }
      q3 = ->(rows) { rows.select { |row| Date.iso8601(row[:date]).between?(Date.new(2026, 7, 1), Date.new(2026, 9, 30)) } }
      per_partner = sales.group_by { |row| row[:partner] }.transform_values { |rows| rows.sum(&gross) }
      biggest = per_partner.max_by { |_, amount| amount }
      net_sales = sales.sum { |row| BigDecimal(row[:net]) }
      net_purchases = purchases.sum { |row| BigDecimal(row[:net]) }
      {
        "customers_total" => sales.sum(&gross), "customers_overdue" => overdue.call(sales).sum(&gross), "acme_total" => per_partner.fetch(:acme), "bravo_total" => per_partner.fetch(:bravo),
        "charlie_total" => per_partner.fetch(:charlie), "largest_debtor_amount" => biggest.last, "largest_debtor" => PARTNERS.fetch(biggest.first).first,
        "over_60_total" => older_than.call(sales, 60).sum(&gross), "over_60_lines" => older_than.call(sales, 60).size,
        "suppliers_total" => purchases.sum(&gross), "suppliers_overdue" => overdue.call(purchases).sum(&gross),
        "revenue" => net_sales, "expenses" => net_purchases, "result" => net_sales - net_purchases,
        "vat_collected" => sales.sum { |row| row[:vat] }, "vat_deductible" => purchases.sum { |row| row[:vat] },
        "q3_vat_collected" => q3.call(sales).sum { |row| row[:vat] }, "q3_vat_deductible" => q3.call(purchases).sum { |row| row[:vat] },
        "trial_balance_debit_total" => sales.sum(&gross) + net_purchases + purchases.sum { |row| row[:vat] }
      }.transform_values { |value| value.is_a?(BigDecimal) ? Agent::ToolResult.money(value) : value.to_s }
    end

    def self.vat(net) = (BigDecimal(net) * VAT_RATE).round(2)

    # The entity, built once: found again on the next call. Needs the VAT reference data and the chart of accounts of the application.
    def self.build!
      existing = ActsAsTenant.without_tenant { Entity.find_by(name: ENTITY_NAME) }
      return built_from(existing) if existing

      ActsAsTenant.without_tenant { new.build }
    end

    def self.built_from(entity)
      ActsAsTenant.without_tenant do
        Built.new(entity: entity, accountant: User.find_by!(email: EMAILS[:accountant]), reader: User.find_by!(email: EMAILS[:reader]))
      end
    end

    def build
      Seeders::VatCodesSeeder.call
      entity = nil
      ApplicationRecord.transaction do
        accountant = user(:accountant, "Eval Accountant")
        reader = user(:reader, "Eval Reader")
        entity = Entity.create!(name: ENTITY_NAME, legal_name: ENTITY_NAME, legal_form: "SRL", country: "BE", active: true, created_by: accountant, features: Entity::FEATURES.index_with { true })
        UserEntity.create!(user: accountant, entity: entity, role: :accountant)
        UserEntity.create!(user: reader, entity: entity, role: :manager)
        ActsAsTenant.with_tenant(entity) { fill }
        return Built.new(entity: entity, accountant: accountant, reader: reader)
      end
    end

    private

    def user(role, name) = User.create!(full_name: name, email: EMAILS.fetch(role), password: SecureRandom.hex(16), role: role == :accountant ? :accountant : :manager)

    def fill
      Seeders::PcmnSeeder.call(entity: ActsAsTenant.current_tenant)
      Seeders::JournalsSeeder.call
      Accounting::FiscalYear.create!(year: 2025, start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31), status: :closed, closed_at: Date.new(2025, 12, 31))
      @fiscal_year = Accounting::FiscalYear.create!(year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open)
      @partners = PARTNERS.transform_values { |name, type, natural, city| Accounting::Partner.create!(name: name, partner_type: type, is_natural_person: natural, city: city, country: "BE", active: true) }
      SALES.each { |row| invoice(:customer, "700000", row) }
      PURCHASES.each { |row| invoice(:supplier, "600000", row) }
      document
      Accounting::Consistency::Runner.call(trigger: "evaluation", fiscal_year: @fiscal_year)
    end

    def invoice(type, account_code, row)
      entity = ActsAsTenant.current_tenant
      invoice = Accounting::Invoice.create!(entity: entity, partner: @partners.fetch(row[:partner]), fiscal_year: @fiscal_year, invoice_type: type, invoice_date: Date.iso8601(row[:date]),
                                            due_date: Date.iso8601(row[:due]), status: :draft, currency: "EUR", vat_treatment: :domestic)
      Accounting::InvoiceLine.create!(entity: entity, invoice: invoice, account: Accounting::Account.find_by!(code: account_code), description: "Evaluation #{type} invoice", quantity: 1,
                                      unit_price: BigDecimal(row[:net]), vat_rate: BigDecimal("21"), position: 1)
      result = Accounting::PostInvoice.call(invoice: invoice)
      raise "the evaluation dataset could not post an invoice: #{result.message}" if result.failure?
    end

    def document
      bytes = "%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"
      doc = Accounting::Document.new(name: "delta-invoice-2026-05.pdf", content_type: "application/pdf", origin: :manual_upload, kind: :purchase_invoice, status: :inbox,
                                     uploaded_by: User.find_by!(email: EMAILS[:accountant]), sha256: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize)
      doc.file.attach(io: StringIO.new(bytes), filename: doc.name, content_type: "application/pdf")
      doc.save!
    end
  end
end

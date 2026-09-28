# Deterministic reference dataset for reports development (docs/dev/reports/spec.md §15).
#
# Scope: P0 scenarios only (ventes/achats, TVA particulière, lettrage, banque,
# anomalies volontaires) — enough to support R01-R06 and invariants I1-I5.
# The P1-P3 scenarios (immobilisations, régularisations, budget, analytique,
# devises) are added when those report waves are actually built, not
# speculatively now (see docs/dev/reports/QUESTIONS.md for the scoping call).
#
# Idempotent: guarded by the entity's name, like the other Seeders::*.
module Seeders
  class ReferenceLedgerSeeder
    ENTITY_NAME = "LedgerFlow Référence".freeze

    # accounting_journal_entries' actual counterpart accounts (Accounting::GenerateInvoiceJournalEntry
    # ignores the journal's own default_account and always uses these — see Accounting::AccountCodes).
    CUSTOMERS = Accounting::AccountCodes::CUSTOMERS
    SUPPLIERS = Accounting::AccountCodes::SUPPLIERS
    SUSPENSE  = Accounting::AccountCodes::TRANSIT # "nets to zero" suspense account, reused as-is

    # Other real PCMN codes (db/seeds/pcmn_commercial.json) used for the manual OD scenarios.
    CASH          = "100000"
    BANK_1        = "550100"
    BANK_2        = "550200"
    INTERNAL_XFER = "580000"
    EXPENSE       = "600000"
    REVENUE       = "700000"

    def self.call
      new.call
    end

    def call
      existing = Entity.find_by(name: ENTITY_NAME)
      return existing if existing

      Seeders::VatCodesSeeder.call # VAT law data, not tenant-scoped; the postings below need it
      entity = nil
      ApplicationRecord.transaction do
        entity = create_entity
        ActsAsTenant.with_tenant(entity) do
          Seeders::PcmnSeeder.call(entity: entity)
          Seeders::JournalsSeeder.call

          @entity           = entity
          @fiscal_year_2025 = create_fiscal_year(2025, :closed)
          @fiscal_year_2026 = create_fiscal_year(2026, :open)
          @customer         = create_partner(:customer, "Client de référence")
          @supplier         = create_partner(:supplier, "Fournisseur de référence")
          @bank_1, @bank_2  = create_bank_accounts

          opening_balances
          sales_and_purchases
          special_vat
          lettering_scenarios
          bank_scenarios
          deliberate_anomalies
        end
      end

      puts "[ReferenceLedger] '#{entity.name}' créée (id=#{entity.id})."
      entity
    end

    private

    attr_reader :entity, :fiscal_year_2025, :fiscal_year_2026, :customer, :supplier, :bank_1, :bank_2

    def create_entity
      Entity.create!(
        name: ENTITY_NAME, legal_name: ENTITY_NAME, legal_form: "SRL", country: "BE",
        vat_number: "BE0123456789", active: true, created_by: User.first || create_seed_user
      )
    end

    def create_seed_user
      User.create!(full_name: "Reference Seed", email: "reference-seed@ledgerflow.test",
                    password: SecureRandom.hex(16), role: :admin)
    end

    def create_fiscal_year(year, status)
      Accounting::FiscalYear.create!(
        year: year, start_date: Date.new(year, 1, 1), end_date: Date.new(year, 12, 31),
        status: status, closed_at: status == :closed ? Date.new(year, 12, 31) : nil
      )
    end

    def create_partner(type, name)
      Accounting::Partner.create!(
        name: name, partner_type: type, vat_number: type == :customer ? "BE0987654321" : "BE0111222333",
        country: "BE", active: true
      )
    end

    def create_bank_accounts
      bnq2 = Accounting::Journal.find_or_create_by!(code: "BNQ2") do |j|
        j.label_fr = "Banque 2"; j.journal_type = :bank; j.sequence_prefix = "BNQ2"
        j.default_account = Accounting::Account.find_by!(code: BANK_2)
      end
      bank_1 = Accounting::BankAccount.create!(journal: Accounting::Journal.find_by!(code: "BNQ"),
        iban: "BE68539007547034", bic: "BBRUBEBB", label_fr: "Compte principal", currency: "EUR", active: true)
      bank_2 = Accounting::BankAccount.create!(journal: bnq2,
        iban: "BE71096123456769", bic: "GKCCBEBB", label_fr: "Compte secondaire", currency: "EUR", active: true)
      [ bank_1, bank_2 ]
    end

    # Opening equity → cash entry at the start of 2025. No closing entries exist yet to actually
    # close a fiscal year (clôture is explicitly hors périmètre, spec §1), so 2026 simply continues
    # on the same account balances rather than carrying formal à-nouveaux.
    def opening_balances
      post_od(fiscal_year_2025, fiscal_year_2025.start_date, "Apport en capital", [
        [ BANK_1, :debit, 10_000 ], [ CASH, :credit, 10_000 ]
      ])
    end

    def sales_and_purchases
      invoice(:customer, vat_rate: 21, label: "Prestation de conseil")
      invoice(:customer, vat_rate: 6, label: "Livre technique")
      invoice(:supplier, vat_rate: 21, label: "Fournitures de bureau")
      credit_note(invoice(:customer, vat_rate: 21, label: "Prestation partiellement annulée").invoice)
    end

    def special_vat
      invoice(:customer, vat_rate: 0, label: "Livraison intracommunautaire", vat_treatment: :intracom_goods)
      invoice(:supplier, vat_rate: 0, label: "Service intracommunautaire reçu", vat_treatment: :intracom_services)
      invoice(:customer, vat_rate: 0, label: "Vente à l'exportation", vat_treatment: :export)
      invoice(:supplier, vat_rate: 21, label: "Travaux immobiliers (autoliquidation)",
              vat_treatment: :construction_reverse_charge)
      # Partial VAT deduction is modeled at entity level (vat_prorata_rate), not per line/code as
      # the spec's §10 vat_codes table would — that table doesn't exist yet (docs/dev/reports/QUESTIONS.md).
      entity.update!(vat_prorata_rate: 80)
    end

    def lettering_scenarios
      # Full: two opposite lines on 440, same amount.
      a = post_od_line(fiscal_year_2026, SUPPLIERS, :debit, 200, partner: supplier)
      b = post_od_line(fiscal_year_2026, SUPPLIERS, :credit, 200, partner: supplier)
      check! Accounting::LetterLines.call(lines: [ a, b ])

      # Partial: an invoice partly paid.
      inv_line = invoice(:supplier, vat_rate: 21, label: "Facture partiellement payée", amount: 1000).line
      payment  = post_od_line(fiscal_year_2026, SUPPLIERS, :debit, 600, partner: supplier)
      check! Accounting::AllocateLines.call(lines: [ inv_line, payment ])

      # Grouped: three lines balancing together.
      c = post_od_line(fiscal_year_2026, SUPPLIERS, :credit, 150, partner: supplier)
      d = post_od_line(fiscal_year_2026, SUPPLIERS, :debit, 90, partner: supplier)
      e = post_od_line(fiscal_year_2026, SUPPLIERS, :debit, 60, partner: supplier)
      check! Accounting::LetterLines.call(lines: [ c, d, e ])

      # Balanced group left unlettered on purpose (R05's "groupes équilibrés non lettrés").
      post_od_line(fiscal_year_2026, SUPPLIERS, :credit, 75, partner: supplier)
      post_od_line(fiscal_year_2026, SUPPLIERS, :debit, 75, partner: supplier)
    end

    def bank_scenarios
      # Reconciled: booked and on the statement.
      entry = post_od(fiscal_year_2026, Date.current - 10, "Encaissement client", [
        [ BANK_1, :debit, 300 ], [ CUSTOMERS, :credit, 300 ]
      ])
      bank_1.transactions.create!(transaction_date: Date.current - 10, amount: 300, currency: "EUR",
        description: "Encaissement client", reference: "REF-RECONCILED", status: :reconciled,
        journal_entry: entry, raw_data: {})

      # BN — booked, not yet on any statement (chèque en transit).
      post_od(fiscal_year_2026, Date.current - 3, "Chèque émis non débité", [
        [ SUPPLIERS, :debit, 80 ], [ BANK_1, :credit, 80 ]
      ])

      # SN — on the statement, not booked yet.
      bank_1.transactions.create!(transaction_date: Date.current - 1, amount: -45, currency: "EUR",
        description: "Frais bancaires non comptabilisés", reference: "REF-UNBOOKED", status: :pending, raw_data: {})

      # Grouped payment: one transaction settling several invoices via one journal entry.
      grouped_entry = post_od(fiscal_year_2026, Date.current - 5, "Paiement groupé fournisseur", [
        [ SUPPLIERS, :debit, 250 ], [ BANK_1, :credit, 250 ]
      ])
      bank_1.transactions.create!(transaction_date: Date.current - 5, amount: -250, currency: "EUR",
        description: "Paiement groupé", reference: "REF-GROUPED", status: :reconciled,
        journal_entry: grouped_entry, raw_data: {})

      # Internal transfer between the two reference bank accounts, via a transit account.
      transfer_out = post_od(fiscal_year_2026, Date.current - 2, "Virement interne (sortie)", [
        [ INTERNAL_XFER, :debit, 500 ], [ BANK_1, :credit, 500 ]
      ])
      transfer_in = post_od(fiscal_year_2026, Date.current - 2, "Virement interne (entrée)", [
        [ INTERNAL_XFER, :credit, 500 ], [ BANK_2, :debit, 500 ]
      ])
      bank_1.transactions.create!(transaction_date: Date.current - 2, amount: -500, currency: "EUR",
        description: "Virement interne", reference: "REF-TRANSFER-OUT", status: :reconciled,
        journal_entry: transfer_out, raw_data: {})
      bank_2.transactions.create!(transaction_date: Date.current - 2, amount: 500, currency: "EUR",
        description: "Virement interne", reference: "REF-TRANSFER-IN", status: :reconciled,
        journal_entry: transfer_in, raw_data: {})
    end

    # Only the anomalies that can exist in the DB as-is: an unbalanced entry is rejected outright
    # by the enforce_double_entry_check trigger (checked per entry, not deferrable past commit),
    # so C01 can't be seeded this way — see docs/dev/reports/QUESTIONS.md.
    def deliberate_anomalies
      # Duplicate: same partner, amount, date and reference.
      2.times do
        post_od(fiscal_year_2026, Date.current - 7, "Facture Lyreco #DUP-001", [
          [ EXPENSE, :debit, 42 ], [ SUPPLIERS, :credit, 42 ]
        ], partner: supplier, reference: "DUP-001")
      end

      # Inverted balance: a customer account (400, normally debtor) left creditor.
      post_od(fiscal_year_2026, Date.current - 6, "Avoir client non compensé", [
        [ CUSTOMERS, :credit, 120 ], [ REVENUE, :debit, 120 ]
      ], partner: customer)

      # Numbering gap: skip a reference in the sales journal.
      journal = Accounting::Journal.find_by!(code: "VTE")
      gap_entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: fiscal_year_2026,
        entry_date: Date.current, description: "Ecriture après trou de numérotation",
        reference: "#{journal.sequence_prefix}#{Date.current.year}/0099", status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      gap_entry.lines.create!(account: Accounting::Account.find_by!(code: EXPENSE), debit: 10, credit: 0)
      gap_entry.lines.create!(account: Accounting::Account.find_by!(code: SUPPLIERS), debit: 0, credit: 10)
      result = Accounting::PostJournalEntry.call(entry: gap_entry)
      raise result.message if result.failure?
    end

    # --- helpers -------------------------------------------------------------

    def check!(result)
      raise result.message if result.failure?

      result
    end

    def post_od(fiscal_year, date, description, sides, partner: nil, reference: nil)
      journal = Accounting::Journal.find_by!(code: "OD")
      entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: fiscal_year, entry_date: date,
        description: description, reference: reference || journal.next_sequence_number(year: date.year),
        status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      sides.each do |code, side, amount|
        entry.lines.create!(account: Accounting::Account.find_by!(code: code), partner: partner,
          label: description, side => BigDecimal(amount.to_s))
      end
      result = Accounting::PostJournalEntry.call(entry: entry)
      raise result.message if result.failure?

      entry
    end

    # A single OD line, its own entry balanced by a technical suspense account (499000) —
    # good enough for lettering fixtures, which only care about the 440/400 line itself.
    def post_od_line(fiscal_year, code, side, amount, partner: nil)
      other_side = side == :debit ? :credit : :debit
      entry = post_od(fiscal_year, Date.current, "Ligne de lettrage", [
        [ code, side, amount ], [ SUSPENSE, other_side, amount ]
      ], partner: partner)
      entry.lines.detect { |l| l.account.code == code }
    end

    Invoiced = Struct.new(:invoice, :line)

    def invoice(type, vat_rate:, label:, vat_treatment: :domestic, amount: 100)
      inv = Accounting::Invoice.create!(entity: entity, partner: type == :customer ? customer : supplier,
        fiscal_year: fiscal_year_2026, invoice_type: type, invoice_date: Date.current, due_date: Date.current + 30,
        status: :draft, currency: "EUR", vat_treatment: vat_treatment)
      account = Accounting::Account.find_by!(code: type == :customer ? REVENUE : EXPENSE)
      Accounting::InvoiceLine.create!(entity: entity, invoice: inv, account: account,
        description: label, quantity: 1, unit_price: BigDecimal(amount.to_s), vat_rate: BigDecimal(vat_rate.to_s),
        position: 1)
      result = Accounting::PostInvoice.call(invoice: inv)
      raise result.message if result.failure?

      counterpart_code = type == :customer ? CUSTOMERS : SUPPLIERS
      line = inv.reload.journal_entry.lines.detect { |l| l.account.code == counterpart_code }
      Invoiced.new(inv, line)
    end

    def credit_note(source_invoice)
      note = source_invoice.build_credit_note
      note.save!
      result = Accounting::PostInvoice.call(invoice: note)
      raise result.message if result.failure?

      note
    end
  end
end

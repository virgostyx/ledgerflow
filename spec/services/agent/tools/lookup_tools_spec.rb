require "rails_helper"

# search_accounts, search_partners and get_journal_entry: the three tools that identify things before the report tools read amounts.
RSpec.describe "The lookup tools of the agent" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: fiscal_year.start_date + 40) }
  let(:registry) { Agent::ToolRegistry.new([ Agent::Tools::SearchAccounts, Agent::Tools::SearchPartners, Agent::Tools::GetJournalEntry ]) }
  let(:purchases) { create(:journal, :purchase) }
  let(:supplier)  { create(:partner, :supplier, name: "Fournisseur Dupont SA", vat_number: nil, city: "Namur") }
  let(:customer)  { create(:partner, name: "Client Martin SRL", vat_number: nil, city: "Liège", partner_type: :customer) }

  def run(name, args) = registry.execute(name, args, context)

  def posted_entry
    entry = create(:journal_entry, journal: purchases, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, status: :draft, reference: nil, description: "Loyer janvier")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal("1210.50"), credit: 0, label: "Loyer")
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: 0, credit: BigDecimal("1210.50"))
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  describe Agent::Tools::SearchAccounts do
    let(:tool) { described_class }
    let(:valid_args) { { "q" => "Clients" } }

    it_behaves_like "an agent tool", permission: "records.view"

    it "finds accounts by the start of the code or by a word of the label, in either language" do
      account_400.update!(label_nl: "Klanten")

      expect(run("search_accounts", { "q" => "4000" })["data"].map { |a| a["code"] }).to eq([ "400000" ])
      expect(run("search_accounts", { "q" => "klanten" })["data"].map { |a| a["code"] }).to eq([ "400000" ])
      expect(run("search_accounts", { "q" => "services" })["data"].first).to include("code" => "604000", "label" => "Services divers", "ref" => "account:#{account_604.id}")
    end

    it "leaves archived accounts out unless asked, and says what filters it applied" do
      account_604.update!(active: false)

      expect(run("search_accounts", { "q" => "604" })["data"]).to be_empty
      found = run("search_accounts", { "q" => "604", "include_inactive" => true })

      expect(found["data"].map { |a| a["code"] }).to eq([ "604000" ])
      expect(found["filters_applied"]).to eq("q" => "604", "include_inactive" => true)
    end

    it "pages: a next_cursor when there is more, and the rows after it on the next call" do
      first = run("search_accounts", { "q" => "4", "limit" => 1 })

      expect(first["data"].size).to eq(1)
      expect(first["truncated"]).to be true
      second = run("search_accounts", { "q" => "4", "limit" => 1, "cursor" => first["next_cursor"] })
      expect(second["data"].map { |a| a["code"] }).not_to include(*first["data"].map { |a| a["code"] })
    end

    it "refuses a cursor it did not give, and a page size over its maximum" do
      expect(run("search_accounts", { "q" => "4", "cursor" => "forged" })).to include("error" => "invalid_arguments")
      expect(run("search_accounts", { "q" => "4", "limit" => 51 })).to include("error" => "invalid_arguments")
    end

    it "does not reach the accounts of another entity" do
      ActsAsTenant.with_tenant(create(:entity)) { create(:account, code: "999999", label_fr: "Clients ailleurs") }

      expect(run("search_accounts", { "q" => "ailleurs" })["data"]).to be_empty
    end
  end

  describe Agent::Tools::SearchPartners do
    let(:tool) { described_class }
    let(:valid_args) { { "q" => "Dupont" } }

    before { supplier; customer }

    it_behaves_like "an agent tool", permission: "records.view"

    it "finds a partner by a word of the name, the VAT number or the city, with its type" do
      expect(run("search_partners", { "q" => "dupont" })["data"].first).to include("name" => "Fournisseur Dupont SA", "type" => "supplier", "city" => "Namur", "ref" => "partner:#{supplier.id}")
      expect(run("search_partners", { "q" => "liège" })["data"].map { |p| p["name"] }).to eq([ "Client Martin SRL" ])
    end

    it "restricts to customers or to suppliers" do
      expect(run("search_partners", { "q" => "S", "partner_type" => "customer" })["data"].map { |p| p["name"] }).to eq([ "Client Martin SRL" ])
      expect(run("search_partners", { "q" => "S", "partner_type" => "supplier" })["data"].map { |p| p["name"] }).to eq([ "Fournisseur Dupont SA" ])
    end

    it "never gives bank details" do
      supplier.update!(iban: "BE68539007547034")

      expect(run("search_partners", { "q" => "Dupont" }).to_json).not_to include("BE68", "iban")
    end

    it "lists homonyms apart, each with its own reference" do
      twin = create(:partner, :supplier, name: "Fournisseur Dupont SA", vat_number: nil, city: "Mons")

      refs = run("search_partners", { "q" => "Dupont" })["data"].map { |p| p["ref"] }

      expect(refs).to contain_exactly("partner:#{supplier.id}", "partner:#{twin.id}")
    end
  end

  describe Agent::Tools::GetJournalEntry do
    let(:tool) { described_class }
    let!(:entry) { posted_entry }
    let(:valid_args) { { "id" => entry.id } }

    it_behaves_like "an agent tool", permission: "records.view"

    it "returns the entry with its lines and totals, amounts as strings" do
      result = run("get_journal_entry", { "id" => entry.id })
      row = result["data"].first

      expect(row).to include("reference" => entry.reference, "description" => "Loyer janvier", "status" => "posted", "journal" => purchases.code, "ref" => "entry:#{entry.id}")
      expect(row["lines"].map { |l| [ l["account"], l["debit"], l["credit"] ] }).to eq([ [ "604000", "1210.50", "0.00" ], [ "440000", "0.00", "1210.50" ] ])
      expect(row["lines"].last["partner"]).to eq("Fournisseur Dupont SA")
      expect(result["totals"]).to include("debit" => "1210.50", "credit" => "1210.50")
    end

    it "finds the entry by its reference as well" do
      expect(run("get_journal_entry", { "reference" => entry.reference })["data"].first["ref"]).to eq("entry:#{entry.id}")
    end

    it "asks for a reference or an id, and says when it finds nothing" do
      expect(run("get_journal_entry", {})).to include("error" => "invalid_arguments")
      expect(run("get_journal_entry", { "reference" => "NOPE-1" })).to include("error" => "not_found")
    end

    it "does not find an entry of another entity, and does not tell that it exists" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:journal_entry, status: :draft) }

      expect(run("get_journal_entry", { "id" => foreign.id })).to include("error" => "not_found")
    end

    it "is forbidden for a person limited to other journals, with the same words as any refusal" do
      other = create(:journal, :sale)
      membership.update!(journal_ids: [ other.id ])

      expect(run("get_journal_entry", { "id" => entry.id })).to eq(Agent::ToolRegistry::FORBIDDEN.merge("error" => "forbidden"))
    end
  end
end

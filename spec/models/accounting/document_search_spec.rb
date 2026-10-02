require "rails_helper"

# F03 search: the name, the text read from the document and the values read from it, with or without accents.
RSpec.describe Accounting::Document, "search" do
  include_context "with entity"

  def document(name, text: nil, fields: {}, **attrs)
    extraction = { "status" => "done", "fields" => fields.transform_values { |v| { "value" => v, "confirmed" => false } } }
    create(:document, name: name, search_text: text, extracted_data: { "extraction" => extraction }, **attrs)
  end

  let!(:acme)   { document("Facture Électricité mars.pdf", text: "ACME Consulting SPRL Invoice No: INV-2026-0042 Total incl. VAT 1.210,00 EUR", fields: { "invoice_number" => "INV-2026-0042", "total" => "1210.00", "supplier_name" => "ACME Consulting" }) }
  let!(:other)  { document("Contrat bail.pdf", text: "Contrat de bail commercial 2026", fields: { "total" => "800.00" }) }
  let!(:scan)   { document("scan-0001.png", content_type: "image/png", content: sample_png) }

  def names(query) = described_class.search(query).pluck(:name)

  it "finds by a word of the name, whatever the case" do
    expect(names("contrat")).to eq([ "Contrat bail.pdf" ])
    expect(names("CONTRAT")).to eq([ "Contrat bail.pdf" ])
  end

  it "finds with or without accents, in both directions" do
    expect(names("electricite")).to eq([ "Facture Électricité mars.pdf" ])
    expect(names("Électricité")).to eq([ "Facture Électricité mars.pdf" ])
    create(:document, name: "plain.pdf", search_text: "Facture electricite plain")
    expect(names("électricité")).to contain_exactly("Facture Électricité mars.pdf", "plain.pdf")
  end

  it "finds by a word of the text read from the document" do
    expect(names("consulting")).to eq([ "Facture Électricité mars.pdf" ])
    expect(names("bail commercial")).to eq([ "Contrat bail.pdf" ])
  end

  it "finds by an invoice number, whole or in part" do
    expect(names("INV-2026-0042")).to eq([ "Facture Électricité mars.pdf" ])
    expect(names("0042")).to eq([ "Facture Électricité mars.pdf" ])
  end

  it "finds by an amount read from the document" do
    expect(names("1210")).to eq([ "Facture Électricité mars.pdf" ])
    expect(names("800.00")).to eq([ "Contrat bail.pdf" ])
  end

  it "finds by a value a person confirmed, as well as by one that was only proposed" do
    other.update_columns(extracted_data: { "extraction" => { "fields" => { "supplier_name" => { "value" => "Immobilière Dupont", "confirmed" => true } } } })

    expect(names("dupont")).to eq([ "Contrat bail.pdf" ])
    expect(names("immobiliere")).to eq([ "Contrat bail.pdf" ])
  end

  it "wants every word (AND), in any order" do
    expect(names("acme invoice")).to eq([ "Facture Électricité mars.pdf" ])
    expect(names("invoice acme")).to eq([ "Facture Électricité mars.pdf" ])
    expect(names("acme bail")).to be_empty
  end

  it "returns nothing when nothing matches, and everything for a blank query" do
    expect(names("zzzzz")).to be_empty
    expect(names("")).to match_array([ "Facture Électricité mars.pdf", "Contrat bail.pdf", "scan-0001.png" ])
    expect(names(nil).size).to eq(3)
    expect(names("   ").size).to eq(3)
  end

  it "does not let LIKE wildcards or quotes act as such" do
    expect(names("%")).to be_empty
    expect(names("_")).to be_empty
    expect(names("a%c")).to be_empty
    expect(names("'; DROP TABLE accounting_documents; --")).to be_empty
    expect(described_class.count).to eq(3)
  end

  it "looks at the first words only, so that a huge query cannot be turned into a huge SQL" do
    expect { described_class.search(Array.new(200) { |i| "word#{i}" }.join(" ")).to_a }.not_to raise_error
  end

  it "never sees another entity's documents" do
    ActsAsTenant.with_tenant(create(:entity)) { create(:document, name: "secret-acme.pdf", search_text: "acme") }

    expect(names("acme")).to eq([ "Facture Électricité mars.pdf" ])
  end

  it "follows the text when it changes (a document read again)" do
    scan.update_columns(search_text: "newly read words")

    expect(names("newly")).to eq([ "scan-0001.png" ])
  end

  it "can be served by the trigram index (shown on a store of 3000 documents, with sequential scans ruled out)" do
    connection = described_class.connection
    connection.execute(<<~SQL)
      INSERT INTO accounting_documents (entity_id, name, byte_size, sha256, search_text, created_at, updated_at)
      SELECT #{entity.id}, 'bulk-' || n, 1, md5(n::text) || md5((n + 1)::text), md5(n::text) || ' ' || md5((n * 7)::text), now(), now()
      FROM generate_series(1, 3000) AS n
    SQL
    connection.execute("ANALYZE accounting_documents")
    connection.execute("SET LOCAL enable_seqscan = off")

    # unscoped: the entity predicate would offer the ordinary entity_id index as a competitor
    plan = connection.select_values("EXPLAIN #{described_class.unscoped.search('consulting').to_sql}").join("\n")

    expect(plan).to include("Bitmap Index Scan on idx_documents_search_blob")
  end

  describe "filters" do
    let(:partner) { create(:partner, :supplier) }

    it "by partner: a document linked to them, naming them, or linked to one of their invoices" do
      linked = create(:document, name: "linked.pdf")
      Accounting::LinkDocument.call(document: linked, target: partner, user: create(:user))
      named = document("named.pdf", fields: { "supplier_partner_id" => partner.id })
      invoice = create(:invoice, :supplier, partner: partner, fiscal_year: create(:fiscal_year, year: 2031, start_date: Date.new(2031, 1, 1), end_date: Date.new(2031, 12, 31)))
      via_invoice = create(:document, name: "via-invoice.pdf")
      Accounting::LinkDocument.call(document: via_invoice, target: invoice, user: create(:user))

      expect(described_class.for_partner(partner.id).pluck(:name)).to contain_exactly("linked.pdf", "named.pdf", "via-invoice.pdf")
      expect(described_class.for_partner(create(:partner, :supplier).id)).to be_empty
    end

    it "by period: the invoice date read from the document, else the day it was uploaded" do
      dated = document("dated.pdf", fields: { "invoice_date" => "2026-03-12" })
      undated = create(:document, name: "undated.pdf")
      undated.update_columns(created_at: Time.zone.local(2026, 5, 20, 10))

      expect(described_class.dated(Date.new(2026, 3, 1), Date.new(2026, 3, 31)).pluck(:name)).to eq([ "dated.pdf" ])
      expect(described_class.dated(Date.new(2026, 5, 1), Date.new(2026, 5, 31)).pluck(:name)).to eq([ "undated.pdf" ])
      expect(described_class.dated(Date.new(2026, 3, 12), nil).pluck(:name)).to include("dated.pdf", "undated.pdf")
      expect(described_class.dated(nil, Date.new(2026, 3, 12)).pluck(:name)).to include("dated.pdf")
      expect(dated).to be_persisted
    end

    it "by amount: the total read from the document" do
      expect(described_class.amount_between(1000, 2000).pluck(:name)).to eq([ "Facture Électricité mars.pdf" ])
      expect(described_class.amount_between(nil, 900).pluck(:name)).to eq([ "Contrat bail.pdf" ])
      expect(described_class.amount_between(900, nil).pluck(:name)).to eq([ "Facture Électricité mars.pdf" ])
    end

    it "does not trip over a value that is not a number" do
      document("odd.pdf", fields: { "total" => "n/a" })

      expect { described_class.amount_between(1, 2).to_a }.not_to raise_error
    end

    it "combines with the search" do
      expect(described_class.search("consulting").amount_between(1000, nil).pluck(:name)).to eq([ "Facture Électricité mars.pdf" ])
      expect(described_class.search("consulting").amount_between(5000, nil)).to be_empty
    end
  end
end

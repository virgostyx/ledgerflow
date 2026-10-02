require "rails_helper"

RSpec.describe "Accounting::Documents", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let(:reader)     { create(:user, role: :auditor) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:memberships) do
    [ create(:user_entity, :admin, user: owner, entity: entity), create(:user_entity, :accountant, user: accountant, entity: entity),
      create(:user_entity, :assistant, user: assistant, entity: entity), create(:user_entity, :manager, user: reader, entity: entity),
      create(:user_entity, :auditor, user: auditor, entity: entity) ]
  end

  before { sign_in accountant }

  def uploaded(content, filename, type = "application/octet-stream") = Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: filename)

  def audit(action) = Accounting::AuditLog.where(action: action, entity_id: entity.id)

  describe "the feature flag" do
    it "closes the screens while f03 is off and uploads nothing" do
      entity.update!(features: { "f03" => false })

      get accounting_documents_path
      expect(response).to redirect_to(accounting_root_path)

      expect { post accounting_documents_path, params: { files: [ uploaded(sample_pdf, "a.pdf") ] } }.not_to change(Accounting::Document, :count)
    end

    it "is turned on by the owner in the entity settings" do
      entity.update!(features: { "f03" => false })
      sign_out accountant
      sign_in owner

      patch accounting_settings_entity_path, params: { entity: { features: { f03: "1" } } }

      expect(entity.reload.feature?(:f03)).to be true
    end
  end

  describe "GET /accounting/documents (the inbox)" do
    let!(:inbox)    { create(:document, name: "inbox-one.pdf") }
    let!(:linked)   { create(:document, name: "linked-one.pdf", status: :linked, kind: :purchase_invoice) }
    let!(:archived) { create(:document, name: "archived-one.pdf", status: :archived) }

    it "lists the live documents, not the archived ones" do
      get accounting_documents_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("inbox-one.pdf", "linked-one.pdf")
      expect(response.body).not_to include("archived-one.pdf")
    end

    it "filters by status, by kind and by name" do
      get accounting_documents_path(status: "inbox")
      expect(response.body).to include("inbox-one.pdf")
      expect(response.body).not_to include("linked-one.pdf")

      get accounting_documents_path(status: "archived")
      expect(response.body).to include("archived-one.pdf")

      get accounting_documents_path(kind: "purchase_invoice")
      expect(response.body).to include("linked-one.pdf")
      expect(response.body).not_to include("inbox-one.pdf")

      get accounting_documents_path(q: "inbox")
      expect(response.body).to include("inbox-one.pdf")
      expect(response.body).not_to include("linked-one.pdf")
    end

    it "says so when there is nothing" do
      get accounting_documents_path(q: "nothing-matches-this")

      expect(response.body).to include("No documents")
    end

    it "never lists another entity's documents" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:document, name: "their-secret.pdf") }

      get accounting_documents_path

      expect(response.body).not_to include("their-secret.pdf")
      expect(foreign).to be_persisted
    end

    it "is open to every role that may view documents" do
      [ reader, auditor, assistant, owner ].each do |user|
        sign_out accountant
        sign_in user
        get accounting_documents_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /accounting/documents (upload)" do
    it "takes several files at once and reports each refusal with its reason" do
      params = { files: [ uploaded(sample_pdf("one"), "one.pdf"), uploaded(sample_png, "two.png"), uploaded(sample_exe, "evil.pdf"), uploaded("", "empty.pdf") ] }

      expect { post accounting_documents_path, params: params }.to change(Accounting::Document, :count).by(2)

      expect(response).to redirect_to(accounting_documents_path)
      expect(flash[:notice]).to match(/2 documents? uploaded/i)
      expect(flash[:alert]).to include("evil.pdf", "empty.pdf")
    end

    it "answers a script (drag and drop with progress) with a bare 200 and keeps the messages for the next page" do
      params = { files: [ uploaded(sample_pdf("dnd"), "dnd.pdf"), uploaded(sample_exe, "evil.pdf") ] }

      expect { post accounting_documents_path, params: params, headers: { "Accept" => "application/json" } }.to change(Accounting::Document, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_blank
      expect(flash[:notice]).to match(/1 document uploaded/i)
      expect(flash[:alert]).to include("evil.pdf")
    end

    it "refuses the same file twice and points to the first" do
      post accounting_documents_path, params: { files: [ uploaded(sample_pdf("dup"), "first.pdf") ] }
      post accounting_documents_path, params: { files: [ uploaded(sample_pdf("dup"), "second.pdf") ] }

      expect(Accounting::Document.count).to eq(1)
      expect(flash[:alert]).to include("second.pdf", "first.pdf")
    end

    it "classifies the upload when a kind is chosen" do
      post accounting_documents_path, params: { kind: "purchase_invoice", files: [ uploaded(sample_pdf("kind"), "k.pdf") ] }

      expect(Accounting::Document.last).to be_purchase_invoice
      expect(Accounting::Document.last.uploaded_by).to eq(accountant)
    end

    it "unpacks a ZIP archive: each file inside becomes a document, and the archive itself is not kept" do
      archive = Accounting::Zipper.build([ [ "a.pdf", sample_pdf("a") ], [ "b.png", sample_png ], [ "bad.pdf", sample_exe ] ])

      expect { post accounting_documents_path, params: { files: [ uploaded(archive, "batch.zip", "application/zip") ] } }.to change(Accounting::Document, :count).by(2)

      expect(Accounting::Document.pluck(:name)).to contain_exactly("a.pdf", "b.png")
      expect(flash[:notice]).to match(/2 documents uploaded/i)
      expect(flash[:alert]).to include("batch.zip / bad.pdf")
    end

    it "mentions archives on the upload form" do
      get accounting_documents_path

      expect(response.body).to match(/ZIP/)
    end

    it "asks to choose a file when there is none" do
      post accounting_documents_path

      expect(flash[:alert]).to match(/choose/i)
    end

    it "is allowed to an assistant and refused to a reader and an external auditor" do
      sign_out accountant
      sign_in assistant
      expect { post accounting_documents_path, params: { files: [ uploaded(sample_pdf("a"), "a.pdf") ] } }.to change(Accounting::Document, :count).by(1)

      [ reader, auditor ].each do |user|
        sign_out assistant
        sign_in user
        expect { post accounting_documents_path, params: { files: [ uploaded(sample_pdf("b#{user.id}"), "b.pdf") ] } }.not_to change(Accounting::Document, :count)
      end
    end
  end

  describe "GET /accounting/documents/:id (the viewer)" do
    it "shows a PDF in the page, with its details" do
      document = create(:document, name: "viewer.pdf", kind: :purchase_invoice)

      get accounting_document_path(document)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("viewer.pdf", file_accounting_document_path(document), "<iframe")
      expect(response.body).to include(document.sha256)
    end

    it "shows an image as an image" do
      document = create(:document, name: "pic.png", content_type: "image/png", content: sample_png)

      get accounting_document_path(document)

      expect(response.body).to include("<img", file_accounting_document_path(document))
    end

    it "offers a download, not a viewer, for a spreadsheet" do
      document = create(:document, name: "book.xlsx", content_type: Accounting::UploadDocument::XLSX, content: sample_xlsx)

      get accounting_document_path(document)

      expect(response.body).to include(download_accounting_document_path(document))
      expect(response.body).not_to include("<iframe")
    end

    it "lists what the document is linked to, linking to it" do
      document = create(:document)
      entry = create(:journal_entry, reference: "ACH-LINKED-1", fiscal_year: fiscal_year)
      Accounting::LinkDocument.call(document: document, target: entry, user: accountant)

      get accounting_document_path(document)

      expect(response.body).to include("ACH-LINKED-1", accounting_journal_entry_path(entry))
    end

    it "is a 404 for another entity's document" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:document) }

      get accounting_document_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /accounting/documents/:id/file (served through the app, never by a public address)" do
    it "serves a PDF inline, untouched, with nosniff" do
      content = sample_pdf("inline")
      document = create(:document, content: content)

      get file_accounting_document_path(document)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to start_with("inline")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.body.b).to eq(content.b)
    end

    it "never shows an XML, a spreadsheet or a CSV in the page: always a download, sealed against scripts" do
      { "x.xml" => [ sample_ubl, "application/xml" ], "b.csv" => [ sample_csv, "text/csv" ], "b.xlsx" => [ sample_xlsx, Accounting::UploadDocument::XLSX ] }.each do |name, (content, type)|
        document = create(:document, name: name, content_type: type, content: content)

        get file_accounting_document_path(document)

        expect(response.headers["Content-Disposition"]).to start_with("attachment")
        expect(response.headers["Content-Security-Policy"]).to include("default-src 'none'")
      end
    end

    it "is refused for another entity's document (the link is tied to the entity and the right)" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:document) }

      get file_accounting_document_path(foreign)

      expect(response).to have_http_status(:not_found)
    end

    it "requires to be signed in" do
      document = create(:document)
      sign_out accountant

      get file_accounting_document_path(document)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "does not audit a simple viewing" do
      document = create(:document)

      expect { get file_accounting_document_path(document) }.not_to change { audit("document_download").count }
    end
  end

  describe "GET /accounting/documents/:id/download" do
    it "sends the file as an attachment and audits the download" do
      document = create(:document, name: "bill.pdf")

      get download_accounting_document_path(document)

      expect(response.headers["Content-Disposition"]).to start_with("attachment")
      expect(response.headers["Content-Disposition"]).to include("bill.pdf")
      expect(audit("document_download").sole.auditable_id).to eq(document.id)
    end
  end

  describe "PATCH /accounting/documents/:id (classify)" do
    it "changes the kind" do
      document = create(:document)

      patch accounting_document_path(document), params: { kind: "contract" }

      expect(document.reload).to be_contract
    end

    it "refuses to reclassify what justifies a validated entry" do
      document = create(:document)
      Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted, fiscal_year: fiscal_year), user: accountant)

      patch accounting_document_path(document), params: { kind: "contract" }

      expect(document.reload).to be_other
      expect(flash[:alert]).to match(/archived/i)
    end

    it "is refused to a reader" do
      document = create(:document)
      sign_out accountant
      sign_in reader

      patch accounting_document_path(document), params: { kind: "contract" }

      expect(document.reload).to be_other
    end
  end

  describe "POST /accounting/documents/:id/archive" do
    it "archives, even what justifies a validated entry, and audits it" do
      document = create(:document)
      Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted, fiscal_year: fiscal_year), user: accountant)

      post archive_accounting_document_path(document)

      expect(document.reload).to be_archived
      expect(audit("document_archive").count).to eq(1)
    end

    it "is refused to an assistant" do
      document = create(:document)
      sign_out accountant
      sign_in assistant

      post archive_accounting_document_path(document)

      expect(document.reload).to be_inbox
    end
  end

  describe "DELETE /accounting/documents/:id" do
    let!(:document) { create(:document) }

    before do
      sign_out accountant
      sign_in owner
    end

    it "is refused before the end of the retention period, and audits nothing" do
      expect { delete accounting_document_path(document) }.not_to change(Accounting::Document, :count)

      expect(flash[:alert]).to match(/retention/i)
      expect(audit("document_delete")).to be_empty
    end

    it "is refused under a legal hold" do
      document.update!(legal_hold: true, legal_hold_reason: "Dispute")

      travel_to(document.retention_until + 1) do
        expect { delete accounting_document_path(document) }.not_to change(Accounting::Document, :count)
      end
    end

    it "is possible for the owner after the term, and audited" do
      travel_to(document.retention_until + 1) do
        expect { delete accounting_document_path(document) }.to change(Accounting::Document, :count).by(-1)
      end

      expect(audit("document_delete").sole.payload).to include("name" => document.name, "sha256" => document.sha256)
    end

    it "is not offered to an accountant, even after the term" do
      sign_out owner
      sign_in accountant

      travel_to(document.retention_until + 1) do
        expect { delete accounting_document_path(document) }.not_to change(Accounting::Document, :count)
      end
    end
  end

  describe "what was read from the document" do
    let(:invoice_text) { "ACME Consulting SPRL\nInvoice No: INV-2026-0042\nInvoice date: 12/03/2026\nTotal excl. VAT 1.000,00 EUR\nVAT 21% 210,00 EUR\nTotal incl. VAT 1.210,00 EUR" }
    let(:document) do
      content = Prawn::Document.new { |pdf| invoice_text.each_line { |line| pdf.text line.chomp } }.render
      Accounting::UploadDocument.call(io: StringIO.new(content), filename: "acme.pdf", user: accountant)[:document].tap { |doc| Accounting::ExtractDocument.call(document: doc) }
    end

    def mark(status, **extra) = document.update_columns(extracted_data: document.extracted_data.merge("extraction" => { "status" => status }.merge(extra)))

    it "shows how it was read" do
      get accounting_document_path(document)

      expect(response.body).to include("Read from the text layer")
    end

    it "proposes each field with where it came from, and asks to confirm it" do
      get accounting_document_path(document)

      expect(response.body).to include("Proposed fields", "Invoice number", "INV-2026-0042", "Total incl. VAT 1.210,00 EUR", "page 1", "To confirm")
      expect(response.body).to include(confirm_field_accounting_document_path(document))
    end

    it "flags the proposals it is less sure of" do
      document.update_columns(extracted_data: { "extraction" => { "status" => "done", "method" => "text_layer", "confidence" => 100,
        "fields" => { "total" => { "value" => "250.00", "snippet" => "Amount due: 250,00", "page" => 1, "confidence" => "low", "confirmed" => false } } } })

      get accounting_document_path(document)

      expect(response.body).to include("Check this one")
    end

    it "says when the reading is still going on, failed, not sure or not possible" do
      { "pending" => "Reading in progress", "unreadable" => "cannot be read", "low_confidence" => "not sure enough", "not_applicable" => "Nothing to read" }.each do |status, text|
        mark(status)
        get accounting_document_path(document)
        expect(response.body).to include(text)
      end

      mark("failed", "error" => "disk on fire")
      get accounting_document_path(document)
      expect(response.body).to include("failed", "disk on fire")
    end

    it "shows who confirmed a field" do
      Accounting::ConfirmDocumentField.call(document: document, field: "total", value: "1210.00", user: owner)

      get accounting_document_path(document)

      expect(response.body).to include("Confirmed by #{owner.full_name}")
    end

    describe "POST /accounting/documents/:id/confirm_field" do
      it "confirms, or corrects, a field" do
        post confirm_field_accounting_document_path(document), params: { field: "total", value: "1.200,00" }

        expect(response).to redirect_to(accounting_document_path(document))
        field = document.reload.extracted_data.dig("extraction", "fields", "total")
        expect(field).to include("value" => "1200.00", "confirmed" => true, "confirmed_by" => accountant.id)
      end

      it "says why a value is refused, and keeps the proposal" do
        post confirm_field_accounting_document_path(document), params: { field: "total", value: "abc" }

        expect(flash[:alert]).to match(/not valid/i)
        expect(document.reload.extracted_data.dig("extraction", "fields", "total", "confirmed")).to be false
      end

      it "is refused on a document frozen by a validated entry" do
        Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted, fiscal_year: fiscal_year), user: accountant)

        post confirm_field_accounting_document_path(document), params: { field: "total", value: "1210.00" }

        expect(flash[:alert]).to match(/validated entry/i)
        expect(document.reload.extracted_data.dig("extraction", "fields", "total", "confirmed")).to be false
      end

      it "is allowed to an assistant, refused to a reader" do
        sign_out accountant
        sign_in assistant
        post confirm_field_accounting_document_path(document), params: { field: "invoice_number", value: "INV-2026-0042" }
        expect(document.reload.extracted_data.dig("extraction", "fields", "invoice_number", "confirmed")).to be true

        sign_out assistant
        sign_in reader
        post confirm_field_accounting_document_path(document), params: { field: "total", value: "1210.00" }
        expect(document.reload.extracted_data.dig("extraction", "fields", "total", "confirmed")).to be false
      end
    end

    describe "POST /accounting/documents/:id/rerun" do
      it "reads the document again, in the background" do
        expect { post rerun_accounting_document_path(document) }.to have_enqueued_job(Accounting::ExtractDocumentJob).with(document.id, entity.id)

        expect(document.reload.extracted_data.dig("extraction", "status")).to eq("pending")
        expect(response).to redirect_to(accounting_document_path(document))
      end

      it "keeps what a person confirmed" do
        Accounting::ConfirmDocumentField.call(document: document, field: "total", value: "1200.00", user: owner)

        post rerun_accounting_document_path(document)

        expect(document.reload.extracted_data.dig("extraction", "fields", "total", "value")).to eq("1200.00")
      end

      it "is refused to a reader" do
        id = document.id # uploaded (and queued) now, not inside the expectation
        sign_out accountant
        sign_in reader

        expect { post rerun_accounting_document_path(id) }.not_to have_enqueued_job(Accounting::ExtractDocumentJob)
      end
    end
  end

  describe "the extraction in the list" do
    it "tells the reading status of each document" do
      create(:document, name: "waiting.pdf", extracted_data: { "extraction" => { "status" => "pending" } })
      create(:document, name: "done.pdf", extracted_data: { "extraction" => { "status" => "done" } })

      get accounting_documents_path

      expect(response.body).to include("Reading", "Read")
    end
  end

  describe "creating a draft invoice from a document" do
    let!(:journal)  { create(:journal, :purchase) }
    let!(:supplier) { create(:partner, :supplier, vat_number: "BE0123456749", name: "ACME Consulting") }
    let(:document) do
      text = "VAT BE0123456749\nInvoice No: INV-2026-0042\nInvoice date: #{Date.current.strftime('%d/%m/%Y')}\nTotal incl. VAT 1.210,00 EUR"
      content = Prawn::Document.new { |pdf| text.each_line { |line| pdf.text line.chomp } }.render
      Accounting::UploadDocument.call(io: StringIO.new(content), filename: "acme.pdf", user: accountant)[:document].tap { |doc| Accounting::ExtractDocument.call(document: doc) }
    end

    it "offers it on the document, with the supplier that was recognised" do
      get accounting_document_path(document)

      expect(response.body).to include("Create a draft invoice", create_invoice_accounting_document_path(document), "ACME Consulting")
      expect(response.body).to match(/<option selected="selected" value="#{supplier.id}"/)
    end

    it "creates the draft and opens it, to add the lines" do
      expect { post create_invoice_accounting_document_path(document), params: { partner_id: supplier.id } }.to change(Accounting::Invoice, :count).by(1)

      invoice = Accounting::Invoice.last
      expect(response).to redirect_to(edit_accounting_invoice_path(invoice))
      expect(invoice).to be_draft
      expect(invoice.supplier_reference).to eq("INV-2026-0042")
      expect(document.reload.links.sole.target).to eq(invoice)
      expect(flash[:notice]).to match(/add the lines/i)
    end

    it "needs a supplier" do
      expect { post create_invoice_accounting_document_path(document), params: { partner_id: "" } }.not_to change(Accounting::Invoice, :count)

      expect(flash[:alert]).to match(/choose a supplier/i)
    end

    it "warns about a probable duplicate, and goes through with a reason" do
      create(:invoice, :supplier, partner: supplier, supplier_reference: "INV-2026-0042", fiscal_year: fiscal_year, journal: journal)

      expect { post create_invoice_accounting_document_path(document), params: { partner_id: supplier.id } }.not_to change(Accounting::Invoice, :count)
      expect(flash[:alert]).to match(/already exists/i)

      expect { post create_invoice_accounting_document_path(document), params: { partner_id: supplier.id, override_reason: "Re-issued invoice" } }.to change(Accounting::Invoice, :count).by(1)
      expect(audit("document_duplicate_override").sole.reason).to eq("Re-issued invoice")
    end

    it "is allowed to an assistant and refused to a reader" do
      sign_out accountant
      sign_in assistant
      expect { post create_invoice_accounting_document_path(document), params: { partner_id: supplier.id } }.to change(Accounting::Invoice, :count).by(1)

      other = create(:document, content: sample_pdf("another"))
      sign_out assistant
      sign_in reader
      expect { post create_invoice_accounting_document_path(other), params: { partner_id: supplier.id } }.not_to change(Accounting::Invoice, :count)
    end

    it "does not offer it to a reader" do
      sign_out accountant
      sign_in reader

      get accounting_document_path(document)

      expect(response.body).not_to include("Create a draft invoice")
    end
  end

  describe "searching the documents" do
    let(:supplier) { create(:partner, :supplier, name: "ACME Consulting") }
    let!(:invoice_doc) do
      create(:document, name: "Facture Électricité.pdf", origin: :email, search_text: "Invoice INV-2026-0042 consulting",
                        extracted_data: { "extraction" => { "status" => "done", "fields" => {
                          "total" => { "value" => "1210.00", "confirmed" => false }, "invoice_date" => { "value" => "2026-03-12", "confirmed" => false },
                          "supplier_partner_id" => { "value" => supplier.id, "confirmed" => false } } } })
    end
    let!(:contract_doc) { create(:document, name: "Contrat bail.pdf", search_text: "bail commercial", extracted_data: { "extraction" => { "fields" => { "total" => { "value" => "800.00" } } } }) }

    def listed(**params)
      get accounting_documents_path(params)
      [ invoice_doc, contract_doc ].select { |doc| response.body.include?(doc.name) }.map(&:name)
    end

    it "searches the name, the text read and the values read, with or without accents" do
      expect(listed(q: "electricite")).to eq([ invoice_doc.name ])
      expect(listed(q: "INV-2026-0042")).to eq([ invoice_doc.name ])
      expect(listed(q: "1210")).to eq([ invoice_doc.name ])
      expect(listed(q: "commercial")).to eq([ contract_doc.name ])
    end

    it "filters by supplier, by period, by amount and by origin" do
      expect(listed(partner_id: supplier.id)).to eq([ invoice_doc.name ])
      expect(listed(from: "2026-03-01", to: "2026-03-31")).to eq([ invoice_doc.name ])
      expect(listed(min_amount: "1000")).to eq([ invoice_doc.name ])
      expect(listed(max_amount: "900")).to eq([ contract_doc.name ])
      expect(listed(origin: "email")).to eq([ invoice_doc.name ])
    end

    it "reads amounts the way they are written in Belgium" do
      expect(listed(min_amount: "1.000,00")).to eq([ invoice_doc.name ])
    end

    it "combines the filters" do
      expect(listed(q: "consulting", min_amount: "1000", origin: "email")).to eq([ invoice_doc.name ])
      expect(listed(q: "consulting", min_amount: "5000")).to be_empty
    end

    it "ignores what is not a valid date, amount, partner or origin, instead of failing" do
      expect(listed(from: "not a date", to: "2026-13-45", min_amount: "abc", max_amount: "", partner_id: "x", origin: "nope").size).to eq(2)
      expect(response).to have_http_status(:ok)
    end

    it "does not let a wildcard or a quote through" do
      expect(listed(q: "%")).to be_empty
      expect(listed(q: "'; DROP TABLE accounting_documents; --")).to be_empty
      expect(Accounting::Document.count).to eq(2)
    end

    it "offers the filters, and remembers what was asked" do
      get accounting_documents_path(q: "bail", min_amount: "100")

      expect(response.body).to include('name="q"', 'name="partner_id"', 'name="from"', 'name="to"', 'name="min_amount"', 'name="max_amount"', 'name="origin"')
      expect(response.body).to include('value="bail"', 'value="100"')
    end

    it "lists, in the supplier filter, the suppliers of this entity only" do
      ActsAsTenant.with_tenant(create(:entity)) { create(:partner, :supplier, name: "Foreign Supplier") }

      get accounting_documents_path

      expect(response.body).to include("ACME Consulting")
      expect(response.body).not_to include("Foreign Supplier")
    end

    it "finds archived documents when asked for the archive" do
      contract_doc.update!(status: :archived)

      expect(listed(q: "bail")).to be_empty
      expect(listed(q: "bail", status: "archived")).to eq([ contract_doc.name ])
    end
  end

  describe "splitting a PDF" do
    # let!: the PDF exists before a test counts the documents it creates
    let!(:scan) do
      Accounting::UploadDocument.call(io: StringIO.new(sample_multipage_pdf("Invoice A", "Invoice B", "Invoice C")), filename: "three.pdf", user: accountant, origin: :scan)[:document]
    end

    it "offers it on a PDF of several pages, saying how many" do
      get accounting_document_path(scan)

      expect(response.body).to include("Split this PDF", split_accounting_document_path(scan), "3 pages")
    end

    it "does not offer it on a one-page PDF, an image or a spreadsheet" do
      one = create(:document, content: sample_pdf("one page"))
      image = create(:document, name: "a.png", content_type: "image/png", content: sample_png)
      book = create(:document, name: "a.xlsx", content_type: Accounting::UploadDocument::XLSX, content: sample_xlsx)

      [ one, image, book ].each do |doc|
        get accounting_document_path(doc)
        expect(response.body).not_to include("Split this PDF")
      end
    end

    it "cuts it into documents linked to the parent" do
      expect { post split_accounting_document_path(scan), params: { ranges: "1,2,3" } }.to change(Accounting::Document, :count).by(3)

      expect(response).to redirect_to(accounting_document_path(scan))
      expect(flash[:notice]).to match(/3 documents? created/i)
      expect(scan.reload.children.count).to eq(3)
    end

    it "lists the children on the parent and the parent on each child" do
      post split_accounting_document_path(scan), params: { ranges: "1,2-3" }
      first, second = scan.reload.children.order(:id)

      get accounting_document_path(scan)
      expect(response.body).to include("Cut into", first.name, accounting_document_path(first), second.name)

      get accounting_document_path(first)
      expect(response.body).to include("Cut out of", scan.name, accounting_document_path(scan))
    end

    it "says why the pages are refused, and cuts nothing" do
      expect { post split_accounting_document_path(scan), params: { ranges: "1-3" } }.not_to change(Accounting::Document, :count)
      expect(flash[:alert]).to match(/whole document/i)

      expect { post split_accounting_document_path(scan), params: { ranges: "9" } }.not_to change(Accounting::Document, :count)
      expect(flash[:alert]).to match(/ranges such as/i)
    end

    it "reports the pages that were already cut" do
      post split_accounting_document_path(scan), params: { ranges: "1,2" }

      post split_accounting_document_path(scan), params: { ranges: "2,3" }

      expect(flash[:notice]).to match(/1 document created/i)
      expect(flash[:alert]).to include("page 2")
    end

    it "is allowed to an assistant and refused to a reader" do
      id = scan.id
      sign_out accountant
      sign_in reader
      expect { post split_accounting_document_path(id), params: { ranges: "1,2,3" } }.not_to change(Accounting::Document, :count)

      sign_out reader
      sign_in assistant
      expect { post split_accounting_document_path(id), params: { ranges: "1,2,3" } }.to change(Accounting::Document, :count).by(3)
    end

    it "is closed for a document of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { Accounting::UploadDocument.call(io: StringIO.new(sample_multipage_pdf("x", "y")), filename: "f.pdf", user: accountant)[:document] }

      post split_accounting_document_path(foreign), params: { ranges: "1,2" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the integrity of the stored file" do
    let!(:document) { create(:document, name: "checked.pdf") }

    it "says when it was last verified" do
      Accounting::VerifyDocument.call(document: document)

      get accounting_document_path(document)

      expect(response.body).to include("Verified")
      expect(response.body).not_to include("does not match")
    end

    it "warns loudly when the stored file no longer matches its checksum" do
      tamper_with_stored_file(document)
      Accounting::VerifyDocument.call(document: document)

      get accounting_document_path(document)

      expect(response.body).to include("does not match the checksum recorded")
    end

    it "warns when the stored file is gone" do
      delete_stored_file(document)
      Accounting::VerifyDocument.call(document: document)

      get accounting_document_path(document)

      expect(response.body).to include("file is missing")
    end

    it "says nothing alarming for a document not verified yet" do
      get accounting_document_path(document)

      expect(response.body).to include("Not verified yet")
    end
  end

  describe "what an external auditor is shown" do
    before { skip "ghostscript and ImageMagick are not installed here" unless %w[gs convert identify].all? { |tool| system("which", tool, out: File::NULL, err: File::NULL) } }

    let(:content) { sample_multipage_pdf("Invoice A 100,00", "Invoice B 200,00") }
    let!(:document) { create(:document, name: "bill.pdf", content: content) }

    def subject_of(bytes) = PDF::Reader.new(StringIO.new(bytes)).info[:Subject].to_s

    it "is the PDF with their name on it, in the viewer as well as in the download" do
      sign_out accountant
      sign_in auditor

      get file_accounting_document_path(document)
      expect(response).to have_http_status(:ok)
      expect(response.body.b).not_to eq(content.b)
      expect(subject_of(response.body)).to include(auditor.full_name.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").split.first)

      get download_accounting_document_path(document)
      expect(response.body.b).not_to eq(content.b)
      expect(subject_of(response.body)).to include("Viewed by")
    end

    it "is the original for everyone else" do
      [ accountant, owner, assistant, reader ].each do |user|
        sign_out accountant
        sign_in user
        get file_accounting_document_path(document)
        expect(response.body.b).to eq(content.b)
      end
    end

    it "is an image with their name on it, for a picture" do
      png = create(:document, name: "scan.png", content_type: "image/png", content: sample_png)
      sign_out accountant
      sign_in auditor

      get file_accounting_document_path(png)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.body.b).not_to eq(sample_png.b)
    end

    it "is refused, rather than given unmarked, when the file cannot be marked (a spreadsheet, an XML)" do
      xml = create(:document, name: "i.xml", content_type: "application/xml", content: sample_ubl)
      sign_out accountant
      sign_in auditor

      get download_accounting_document_path(xml)

      expect(response).to redirect_to(accounting_document_path(xml))
      expect(flash[:alert]).to match(/cannot be shown/i)
    end

    it "is given as it is when the owner allows read-only exports, and only then" do
      xml = create(:document, name: "i.xml", content_type: "application/xml", content: sample_ubl)
      entity.update!(read_only_export: true)
      sign_out accountant
      sign_in auditor

      get download_accounting_document_path(xml)

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(sample_ubl.b)
    end

    it "is never the unmarked file when marking fails" do
      allow(Accounting::ExternalCommand).to receive(:run).and_raise(Accounting::ExternalCommand::Failed, "gs is not installed")
      sign_out accountant
      sign_in auditor

      get file_accounting_document_path(document)

      expect(response).not_to have_http_status(:ok)
      expect(response.body.b).not_to eq(content.b)
    end

    it "still audits a download, with who downloaded it" do
      sign_out accountant
      sign_in auditor

      get download_accounting_document_path(document)

      expect(Accounting::AuditLog.where(action: "document_download", auditable_id: document.id).sole.user_id).to eq(auditor.id)
    end

    it "does not offer the auditor a download link that leads nowhere for a document that cannot be marked" do
      xml = create(:document, name: "i.xml", content_type: "application/xml", content: sample_ubl)
      sign_out accountant
      sign_in auditor

      get accounting_document_path(xml)

      expect(response.body).not_to include(download_accounting_document_path(xml))
      expect(response.body).to include("cannot be shown")
    end
  end

  describe "legal hold" do
    let!(:document) { create(:document, name: "held.pdf") }

    it "is placed by the owner, with a reason that everyone who sees the document can read" do
      sign_out accountant
      sign_in owner

      post legal_hold_accounting_document_path(document), params: { hold: "1", reason: "Tax audit 2026" }

      expect(document.reload).to have_attributes(legal_hold: true, legal_hold_reason: "Tax audit 2026")
      sign_out owner
      sign_in reader
      get accounting_document_path(document)
      expect(response.body).to include("Legal hold", "Tax audit 2026")
    end

    it "needs a reason" do
      sign_out accountant
      sign_in owner

      post legal_hold_accounting_document_path(document), params: { hold: "1", reason: "" }

      expect(document.reload.legal_hold).to be false
      expect(flash[:alert]).to match(/reason/i)
    end

    it "is released by the owner, who gives a reason" do
      sign_out accountant
      sign_in owner
      Accounting::SetLegalHold.call(document: document, hold: true, reason: "Dispute", user: owner)

      post legal_hold_accounting_document_path(document), params: { hold: "0", reason: "Settled" }

      expect(document.reload.legal_hold).to be false
    end

    it "is the owner's alone: refused to an accountant and an assistant" do
      [ accountant, assistant ].each do |user|
        sign_out accountant
        sign_in user
        post legal_hold_accounting_document_path(document), params: { hold: "1", reason: "Nope" }
        expect(document.reload.legal_hold).to be false
      end
    end

    it "offers the form to the owner only" do
      get accounting_document_path(document)
      expect(response.body).not_to include(legal_hold_accounting_document_path(document))

      sign_out accountant
      sign_in owner
      get accounting_document_path(document)
      expect(response.body).to include(legal_hold_accounting_document_path(document))
    end

    it "works on a document that justifies a validated entry" do
      Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted, fiscal_year: fiscal_year), user: accountant)
      sign_out accountant
      sign_in owner

      post legal_hold_accounting_document_path(document), params: { hold: "1", reason: "Audit" }

      expect(document.reload.legal_hold).to be true
    end
  end
end

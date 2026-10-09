require "rails_helper"

# B01a, the screens: what waits for me, one invoice to decide on, bulk approval, the section of the invoice, the options.
RSpec.describe "Invoice approval screens (B01a)", type: :request do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:author)      { create(:user, full_name: "Ann Author") }
  let(:owner)       { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant)  { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)   { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:account)     { create(:account) }
  let!(:policy) do
    Approvals::Policy.create!(name: "all", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin accountant])
    end
  end

  def invoice_of(amount, partner: create(:partner, name: "Supplier #{SecureRandom.hex(2)}"), due: Date.current + 10, created_by: author)
    create(:invoice, :supplier, partner: partner, due_date: due, created_by: created_by, fiscal_year: fiscal_year).tap do |i|
      create(:invoice_line, invoice: i, account: account, unit_price: amount, description: "Consulting")
    end
  end

  def submit(invoice) = Approvals::Submit.call(invoice: invoice, user: author)[:request]

  before { sign_in owner }

  describe "the flag and the right" do
    it "is closed when the feature is off" do
      entity.update!(features: entity.features.merge("b01a" => false))

      get accounting_approvals_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "is closed to someone who cannot approve" do
      sign_in assistant

      get accounting_approvals_path

      expect(response).to redirect_to(root_path).or redirect_to(accounting_root_path)
    end
  end

  describe "To approve" do
    it "lists what waits for me, the earliest payment due date first, and nothing that is not mine" do
      late  = submit(invoice_of("100.00", due: Date.current + 30))
      soon  = submit(invoice_of("200.00", due: Date.current + 2))
      other_policy = Approvals::Policy.create!(name: "elsewhere", subject: :purchase_invoice, priority: 0, conditions: { "min_amount" => "5000" })
      other_policy.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ accountant.id ])
      theirs = submit(invoice_of("9000.00")) # for the accountant alone
      done = submit(invoice_of("300.00")).tap { |r| Approvals::Decide.call(request: r, user: owner, decision: :approved, content_fingerprint: r.content_fingerprint) }

      get accounting_approvals_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body.index(soon.subject.partner.name)).to be < body.index(late.subject.partner.name)
      expect(body).not_to include(theirs.subject.partner.name)
      expect(body).not_to include(done.subject.partner.name)
    end

    it "says so when nothing waits" do
      get accounting_approvals_path

      expect(response.body).to include("Nothing waits for your approval")
    end

    it "filters by supplier and by amount" do
      small = submit(invoice_of("100.00", partner: create(:partner, name: "Small Co")))
      big   = submit(invoice_of("5000.00", partner: create(:partner, name: "Big Co")))

      get accounting_approvals_path, params: { supplier: "Big" }
      expect(response.body).to include("Big Co")
      expect(response.body).not_to include("Small Co")

      get accounting_approvals_path, params: { min_amount: "1000" }
      expect(response.body).to include("Big Co")
      expect(response.body).not_to include("Small Co")
      expect([ small, big ]).to all(be_persisted)
    end

    it "shows the shopping list for bulk approval only when the entity allows it" do
      submit(invoice_of("100.00"))

      get accounting_approvals_path
      expect(response.body).not_to include("Approve selected")

      entity.update!(bulk_threshold: 500)
      get accounting_approvals_path
      expect(response.body).to include("Approve selected")
    end
  end

  describe "one invoice" do
    let(:invoice) { invoice_of("1000.00", partner: create(:partner, name: "Acme Ltd")) }
    let!(:request_record) { submit(invoice) }

    it "shows what is needed to decide: the supplier, the lines, the total, the circuit" do
      get accounting_approval_path(request_record)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Ltd", "Consulting", "1.210,00").or include("1,210.00")
      expect(response.body).to include("Level 1")
      expect(response.body).to include("Approve", "Refuse", "Ask for changes")
    end

    it "warns when the amount is far above what the supplier usually costs" do
      3.times { |n| create(:invoice, :supplier, partner: invoice.partner, fiscal_year: fiscal_year, status: :posted, invoice_date: Date.current - (n + 1), invoice_number: "OLD#{n}").update_columns(total_incl_vat: 100) }

      get accounting_approval_path(request_record)

      expect(response.body).to include("more than twice")
    end

    it "shows the decisions already taken, with who and why" do
      policy.steps.first.update!(mode: :all_of, approver_user_ids: [ owner.id, accountant.id ], approver_roles: [])
      Approvals::Decide.call(request: request_record, user: accountant, decision: :approved, content_fingerprint: request_record.content_fingerprint)

      get accounting_approval_path(request_record)

      expect(response.body).to include("Alice Accountant")
    end

    it "does not offer the buttons to someone who is not an approver of this request" do
      other = Approvals::Policy.create!(name: "x", subject: :purchase_invoice, priority: 0)
      request_record.update!(policy: other)
      other.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ accountant.id ])

      get accounting_approval_path(request_record)

      expect(response.body).not_to include("Ask for changes")
    end

    it "approves, and goes back to the list" do
      post decide_accounting_approval_path(request_record), params: { decision: "approved", content_fingerprint: request_record.content_fingerprint }

      expect(response).to redirect_to(accounting_approvals_path)
      expect(request_record.reload).to be_approved
      expect(request_record.decisions.sole.channel).to eq("web")
    end

    it "refuses with a reason, and does not without one" do
      post decide_accounting_approval_path(request_record), params: { decision: "rejected", content_fingerprint: request_record.content_fingerprint }
      expect(response).to redirect_to(accounting_approval_path(request_record))
      expect(flash[:alert]).to match(/reason/i)
      expect(request_record.reload).to be_pending

      post decide_accounting_approval_path(request_record), params: { decision: "rejected", comment: "Wrong price", content_fingerprint: request_record.content_fingerprint }
      expect(request_record.reload).to be_rejected
    end

    it "reloads the invoice when it changed under the approver's eyes" do
      shown = request_record.content_fingerprint
      invoice.lines.first.update!(unit_price: "5000.00")

      post decide_accounting_approval_path(request_record), params: { decision: "approved", content_fingerprint: shown }

      expect(request_record.reload).to be_invalidated
      expect(flash[:alert]).to match(/changed/i)
      expect(response).to redirect_to(accounting_approvals_path)
    end

    it "refuses a decision of someone who is not an approver" do
      sign_in assistant

      post decide_accounting_approval_path(request_record), params: { decision: "approved", content_fingerprint: request_record.content_fingerprint }

      expect(request_record.reload).to be_pending
    end

    it "keeps the author from approving their own invoice" do
      author_owner = create(:user_entity, :admin, user: author, entity: entity).user
      sign_in author_owner

      post decide_accounting_approval_path(request_record), params: { decision: "approved", content_fingerprint: request_record.content_fingerprint }

      expect(request_record.reload).to be_pending
      expect(flash[:alert]).to match(/entered yourself/i)
    end
  end

  describe "bulk approval" do
    let!(:small)  { submit(invoice_of("100.00")) }
    let!(:small2) { submit(invoice_of("200.00")) }
    let!(:big)    { submit(invoice_of("900.00")) } # 1,089.00 incl. VAT

    def bulk(*requests) = post bulk_accounting_approvals_path, params: { request_ids: requests.map(&:id), fingerprints: requests.to_h { |r| [ r.id, r.content_fingerprint ] } }

    it "is off while the entity has no threshold" do
      bulk(small)

      expect(small.reload).to be_pending
      expect(flash[:alert]).to match(/not enabled/i)
    end

    it "approves what is under the threshold, each decision recorded on its own, and says what it left" do
      entity.update!(bulk_threshold: 300)

      bulk(small, small2, big)

      expect([ small, small2 ].map { |r| r.reload.status }).to eq(%w[approved approved])
      expect(big.reload).to be_pending
      expect(Approvals::Decision.where(request_id: [ small.id, small2.id ]).count).to eq(2)
      expect(flash[:notice]).to match(/2 approved/)
      expect(flash[:alert]).to match(/1 left/i)
    end

    it "leaves out an invoice with a warning, whatever its amount" do
      entity.update!(bulk_threshold: 300)
      3.times { |n| create(:invoice, :supplier, partner: small.subject.partner, fiscal_year: fiscal_year, status: :posted, invoice_date: Date.current - (n + 1), invoice_number: "O#{n}").update_columns(total_incl_vat: 10) }

      bulk(small)

      expect(small.reload).to be_pending
    end

    it "does nothing for a request that is not mine" do
      entity.update!(bulk_threshold: 300)
      small.update!(policy: Approvals::Policy.create!(name: "x", subject: :purchase_invoice, priority: 0).tap { |p| p.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ accountant.id ]) })

      bulk(small)

      expect(small.reload).to be_pending
    end
  end

  describe "the section of the invoice" do
    let(:invoice) { invoice_of("1000.00") }

    it "shows where the invoice stands for payment, and the circuit once it started" do
      invoice.update_columns(status: Accounting::Invoice.statuses[:posted])
      request = submit(invoice)
      Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint, comment: nil)

      get accounting_invoice_path(invoice)

      expect(response.body).to include("Approval").and include("Approved")
      expect(response.body).to include("Olga Owner")
    end

    it "offers to submit a purchase invoice that has not been" do
      get accounting_invoice_path(invoice)
      expect(response.body).to include("Submit for approval")

      post submit_for_approval_accounting_invoice_path(invoice)

      expect(response).to redirect_to(accounting_invoice_path(invoice))
      expect(invoice.reload).to be_payment_to_approve
    end

    it "shows nothing on a sales invoice" do
      sale = create(:invoice, :customer, fiscal_year: fiscal_year)

      get accounting_invoice_path(sale)

      expect(response.body).not_to include("Submit for approval")
    end
  end

  describe "the options" do
    it "are the owner's: bap_before_posting, allow_self_approval, bulk_threshold" do
      patch accounting_settings_entity_path, params: { entity: { bap_before_posting: "1", allow_self_approval: "1", bulk_threshold: "250" } }

      expect(entity.reload).to have_attributes(bap_before_posting: true, allow_self_approval: true, bulk_threshold: 250)
    end

    it "are recorded in the audit trail when they change, with who and from what to what, and only then" do
      patch accounting_settings_entity_path, params: { entity: { allow_self_approval: "1", bulk_threshold: "250" } }
      patch accounting_settings_entity_path, params: { entity: { allow_self_approval: "1", bulk_threshold: "250" } } # unchanged

      logs = Accounting::AuditLog.for_record(entity).for_action("approval_option_changed")
      expect(logs.map { |l| l.payload.slice("option", "from", "to") }).to contain_exactly(
        { "option" => "allow_self_approval", "from" => false, "to" => true },
        { "option" => "bulk_threshold", "from" => nil, "to" => "250.0" }
      )
      expect(logs.map(&:user_id).uniq).to eq([ owner.id ])
    end

    it "are not an accountant's to change" do
      sign_in accountant

      patch accounting_settings_entity_path, params: { entity: { bap_before_posting: "1", allow_self_approval: "1", bulk_threshold: "250" } }

      expect(entity.reload).to have_attributes(bap_before_posting: false, allow_self_approval: false, bulk_threshold: nil)
    end
  end

  describe "the menu" do
    it "counts what waits for me" do
      submit(invoice_of("100.00"))
      submit(invoice_of("200.00"))

      get accounting_root_path

      expect(response.body).to match(/To approve.*?>\s*2\s*</m)
    end
  end
end

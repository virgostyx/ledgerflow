require "rails_helper"

# F12b through the screens: the access to every member, the rules that wait for an accountant, the review that blocks, the freezing, the exports.
RSpec.describe "Accounting::Consolidation", type: :request, consolidation: true do
  let(:parents) { parent_and_subsidiary(payable_in_parent: "800.00") }
  let(:parent) { parents.first }
  let(:sub) { parents.last }
  let(:owner) { create(:user, full_name: "Olivia Owner") }
  let(:group) { make_group(parent, members: { sub => { stake: 80 } }) }

  before do
    create(:user_entity, :admin, user: owner, entity: parent)
    create(:user_entity, :accountant, user: owner, entity: sub)
    sign_in owner
  end

  def with_parent = ActsAsTenant.with_tenant(parent) { yield }

  describe "the group" do
    it "is made by a person of the parent, who is in it at 100 %, and gets its members, with the history of the percentage" do
      post accounting_consolidation_groups_path, params: { name: "Holding", currency: "EUR" }
      created = with_parent { Consolidation::Group.find_by!(name: "Holding") }
      expect(with_parent { created.members.map { |m| [ m.member_entity.name, m.stake_on(Date.current).to_s("F") ] } }).to eq([ [ "Parent SA", "100.0" ] ])

      post add_member_accounting_consolidation_group_path(created), params: { entity_id: sub.id, percentage: "80", method: "full" }
      member = with_parent { created.members.find_by(member_entity: sub) }
      post add_stake_accounting_consolidation_group_path(created, member_id: member.id), params: { percentage: "60", effective_on: "2026-07-01" }
      get accounting_consolidation_group_path(created)
      expect(response.body).to include("Sub SRL", "80.0 % from 2000-01-01, 60.0 % from 2026-07-01")

      delete remove_member_accounting_consolidation_group_path(created, member_id: with_parent { created.members.find_by(member_entity: parent) }.id)
      expect(flash[:alert]).to match(/parent company stays/)
    end

    it "is shown to nobody who lacks access to one of its members: refused whole, naming no company" do
      group
      stranger = create(:user)
      create(:user_entity, :admin, user: stranger, entity: parent) # the parent only
      sign_in stranger
      get accounting_consolidation_group_path(group)
      expect(response).to redirect_to(accounting_consolidation_groups_path)
      expect(flash[:alert]).to match(/do not have access to every company of this group \(1 missing\).*refused whole/)

      run = new_run(group)
      get accounting_consolidation_run_path(run)
      expect(flash[:alert]).to match(/1 missing/)
      expect(response).to redirect_to(accounting_consolidation_groups_path)
      expect { post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" } }.not_to change { Consolidation::Run.unscoped.count }
      expect(flash[:alert]).to match(/refused whole/)
      post add_member_accounting_consolidation_group_path(group), params: { entity_id: parent.id, percentage: "10" }
      expect(response).to redirect_to(accounting_consolidation_groups_path)
      expect(response.body).not_to include("Sub SRL")
    end

    it "is closed to a role that may not read it, and to a company that did not turn the feature on" do
      group
      reader = create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: parent); create(:user_entity, :manager, user: u, entity: sub) }
      sign_in reader
      get accounting_consolidation_group_path(group)
      expect(response).to have_http_status(:ok) # a reader reads
      post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" }
      expect(response).not_to have_http_status(:created)
      expect(Consolidation::Run.unscoped.count).to eq(0)

      sign_in owner
      parent.update!(features: { "f12" => false })
      get accounting_consolidation_groups_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "a rule waits for an accountant" do
    it "is recorded by the owner with who, in what capacity, when and where it is written, then applied with the parameters validated" do
      group
      post add_validation_accounting_consolidation_group_path(group), params: { rule_key: "intragroup_balances", validated_by_name: "Jane Doe", validated_by_title: "Chartered accountant, Doe & Co",
                                                                                  validated_on: Date.current.iso8601, reference: "QUESTIONS.md F12 / letter of 5 Oct", parameters: '{"pairs":[["40/41","42/48"]]}' }
      validation = with_parent { group.rule_validations.sole }
      expect(validation).to have_attributes(rule_key: "intragroup_balances", validated_by_name: "Jane Doe", recorded_by: owner, parameters: { "pairs" => [ %w[40/41 42/48] ] })
      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: "consolidation_rule_validated").last.payload }).to include("rule" => "intragroup_balances", "by" => "Jane Doe")

      get accounting_consolidation_group_path(group)
      expect(response.body).to include("Validated", "Doe &amp; Co", "Not applied: no validation recorded")

      post add_validation_accounting_consolidation_group_path(group), params: { rule_key: "intragroup_balances", validated_by_name: "X", validated_by_title: "Y", reference: "Z", validated_on: Date.current.iso8601 }
      expect(flash[:alert]).to match(/already has a validation in force/)
      post add_validation_accounting_consolidation_group_path(group), params: { rule_key: "translation", validated_by_name: "X", validated_by_title: "Y", reference: "Z", validated_on: Date.current.iso8601, parameters: "not json" }
      expect(flash[:alert]).to match(/not valid JSON/)
      post revoke_validation_accounting_consolidation_group_path(group, validation_id: validation.id)
      expect(validation.reload.revoked_at).to be_present
      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: "consolidation_rule_revoked").exists? }).to be(true)
    end

    it "is the owner's: an accountant may prepare the run but not record a validation" do
      group
      accountant = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: parent); create(:user_entity, :accountant, user: u, entity: sub) }
      sign_in accountant
      post add_validation_accounting_consolidation_group_path(group), params: { rule_key: "minority_interests", validated_by_name: "X", validated_by_title: "Y", reference: "Z", validated_on: Date.current.iso8601 }
      expect(with_parent { group.rule_validations.count }).to eq(0)
      post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" }
      expect(response).to redirect_to(accounting_consolidation_run_path(Consolidation::Run.unscoped.last))
    end
  end

  describe "a run" do
    before { %w[intragroup_balances intragroup_flows minority_interests].each { |key| validate_rule(group, key) } }

    it "shows the perimeter, the reconciliation, the entries, the statements and what blocks (criteria 3 to 6 on screen)" do
      post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" }
      run = Consolidation::Run.unscoped.last
      follow_redirect!
      expect(response.body).to include("PROVISIONAL", "Parent SA", "Sub SRL", "80.0", "Intragroup difference of 200.00", "Propose an adjustment", "Minority share of equity".downcase.then { "minority share of equity 5800.0" })
      expect(Nokogiri::HTML(response.body).css("[data-section=review] li.text-red-700").size).to be >= 2 # the balances and the sales differ
      expect(run).to be_draft

      post validate_accounting_consolidation_run_path(run)
      expect(flash[:alert]).to match(/Intragroup difference of 200\.00/)
      expect(run.reload).to be_draft
    end

    it "takes a proposed adjustment from the reconciliation, lets it be reviewed, and then nothing blocks: validated and frozen, with its fingerprint" do
      post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" }
      run = Consolidation::Run.unscoped.last
      context = { kind: "balances", creditor_id: sub.id, debtor_id: parent.id, heading_creditor: "40/41", heading_debtor: "42/48" }
      get new_entry_accounting_consolidation_run_path(run, kind: "intercompany_adjustment", amount: "200.0", comment: "Invoice in transit: ", context: context)
      expect(response.body).to include("42/48", "40/41", "200.0", "Invoice in transit")

      post create_entry_accounting_consolidation_run_path(run), params: { kind: "intercompany_adjustment", comment: "Invoice in transit of 12 December", context: context,
                                                                          lines: { "0" => { statement: "liabilities", code: "42/48", side: "debit", amount: "200" }, "1" => { statement: "assets", code: "40/41", side: "credit", amount: "200" } } }
      expect(with_parent { run.entries.where(kind: "intercompany_adjustment").count }).to eq(1)
      flow_context = { kind: "flows", creditor_id: sub.id, debtor_id: parent.id, heading_creditor: "70", heading_debtor: "61" }
      post create_entry_accounting_consolidation_run_path(run), params: { kind: "intercompany_adjustment", comment: "Same invoice, sales side", context: flow_context,
                                                                          lines: { "0" => { statement: "income", code: "70", side: "debit", amount: "200" }, "1" => { statement: "income", code: "61", side: "credit", amount: "200" } } }

      post validate_accounting_consolidation_run_path(run)
      expect(flash[:notice]).to match(/Validated/)
      post freeze_accounting_consolidation_run_path(run)
      run.reload
      expect(run).to be_frozen
      expect(flash[:notice]).to include(run.snapshot_sha256)
      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: %w[consolidation_run_validated consolidation_run_frozen]).order(:id).pluck(:action) }).to eq(%w[consolidation_run_validated consolidation_run_frozen])

      get accounting_consolidation_run_path(run)
      expect(response.body).to include("Frozen on", run.snapshot_sha256, "the content is intact")
      post compute_accounting_consolidation_run_path(run)
      expect(flash[:alert]).to match(/frozen run is not worked out again/)
      post create_entry_accounting_consolidation_run_path(run), params: { kind: "adjustment", comment: "late", lines: { "0" => { statement: "assets", code: "3", side: "debit", amount: "1" }, "1" => { statement: "liabilities", code: "13", side: "credit", amount: "1" } } }
      expect(flash[:alert]).to match(/run is frozen/)
    end

    it "refuses a dividend without its document, and keeps a rule's own entries out of reach" do
      post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" }
      run = Consolidation::Run.unscoped.last
      post create_entry_accounting_consolidation_run_path(run), params: { kind: "dividends", comment: "Dividend", lines: { "0" => { statement: "assets", code: "3", side: "debit", amount: "5" }, "1" => { statement: "liabilities", code: "13", side: "credit", amount: "5" } } }
      expect(flash[:alert]).to match(/Document is required/)

      document = ActsAsTenant.with_tenant(parent) { create(:document, name: "dividend-decision.pdf") }
      post create_entry_accounting_consolidation_run_path(run), params: { kind: "dividends", comment: "Dividend", document_id: document.id, lines: { "0" => { statement: "assets", code: "3", side: "debit", amount: "5" }, "1" => { statement: "liabilities", code: "13", side: "credit", amount: "5" } } }
      expect(with_parent { run.entries.find_by(kind: "dividends").document }).to eq(document)

      auto = with_parent { run.entries.where.not(rule_key: nil).first }
      delete destroy_entry_accounting_consolidation_run_path(run, entry_id: auto.id)
      expect(flash[:alert]).to match(/not deleted/)
      manual = with_parent { run.entries.find_by(kind: "dividends") }
      delete destroy_entry_accounting_consolidation_run_path(run, entry_id: manual.id)
      expect(with_parent { run.entries.where(kind: "dividends").count }).to eq(0)
    end

    it "is exported to Excel and PDF with the perimeter, the eliminations, the statements, the fingerprint and the PROVISIONAL mark" do
      post accounting_consolidation_runs_path, params: { group_id: group.id, reporting_date: "2026-12-31" }
      run = Consolidation::Run.unscoped.last
      get export_accounting_consolidation_run_path(run, format: :xlsx)
      expect(response.headers["Content-Type"]).to include("spreadsheetml")
      sheet = Imports::Reader.read(response.body, filename: "x.xlsx")
      expect(sheet.rows.map(&:first)).to include("Perimeter", "Eliminations", "Assets", "Liabilities", "Income", "Fingerprint", "Status")
      expect(sheet.rows.flatten.join(" ")).to include("PROVISIONAL", "not frozen", "TOTAL ASSETS")
      get export_accounting_consolidation_run_path(run, format: :pdf)
      expect(response.headers["Content-Type"]).to include("application/pdf")
      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: "consolidation_export").count }).to eq(2)
    end
  end
end

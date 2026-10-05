require "rails_helper"

# F12a: the portfolio shows only the dossiers a person works in, each from its own snapshot, and its grouped actions write no accounting entry.
RSpec.describe "Portfolio", type: :request do
  let(:alice) { create(:user, full_name: "Alice Accountant") }
  let(:bob)   { create(:user, full_name: "Bob Bookkeeper") }
  let!(:acme)    { create(:entity, name: "Acme Fiduciary") }
  let!(:bakery)  { create(:entity, name: "Bakery Shared") }
  let!(:cafe)    { create(:entity, name: "Cafe Secret") }

  before do
    create(:user_entity, :admin, user: alice, entity: acme)
    create(:user_entity, :accountant, user: alice, entity: bakery)
    create(:user_entity, :admin, user: bob, entity: bakery)
    create(:user_entity, :admin, user: bob, entity: cafe)
  end

  def snap(entity, **attrs) = DossierHealthSnapshot.create!({ entity: entity, taken_on: Date.current, computed_at: Time.current }.merge(attrs))

  describe "who sees what (criterion 1: three companies, two users)" do
    before do
      snap(acme, overdue_receivables: BigDecimal("111.11"), blocking_count: 0, warning_count: 1)
      snap(bakery, overdue_receivables: BigDecimal("222.22"), blocking_count: 2, warning_count: 0)
      snap(cafe, overdue_receivables: BigDecimal("333.33"), blocking_count: 0, warning_count: 0)
    end

    it "shows each person only the dossiers they work in, with nothing of the others anywhere on the page" do
      sign_in alice
      get portfolio_path
      expect(response.body).to include("Acme Fiduciary", "111.11", "Bakery Shared", "222.22").and not_include("Cafe Secret").and not_include("333.33")

      sign_in bob
      get portfolio_path
      expect(response.body).to include("Bakery Shared", "222.22", "Cafe Secret", "333.33").and not_include("Acme Fiduciary").and not_include("111.11")
    end

    it "leaves out a dossier that did not turn the feature on, and one whose access has ended" do
      acme.update!(features: { "f12" => false })
      UserEntity.find_by(user: alice, entity: bakery).update_columns(valid_until: 1.day.ago.to_date)
      sign_in alice
      get portfolio_path
      expect(response.body).to include("No dossier in the portfolio")
      expect(Nokogiri::HTML(response.body).css("[data-section=portfolio]")).to be_empty
    end

    it "reads no accounting entry and no query of the books without its entity (criterion 2)" do
      sign_in alice
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get portfolio_path }

      expect(response).to have_http_status(:ok)
      expect(queries.grep(/accounting_journal_entr/)).to eq([])
      expect(queries.select { |sql| sql.match?(/FROM "accounting_/) }.reject { |sql| sql.include?("entity_id") }).to eq([])
      expect(queries.grep(/dossier_health_snapshots/)).not_to be_empty
    end

    it "shows the day of the last calculation, and says so when a dossier has none yet" do
      DossierHealthSnapshot.where(entity: acme).delete_all
      sign_in alice
      get portfolio_path
      expect(response.body).to include("Not calculated yet")
      expect(response.body).to include(I18n.l(Time.current, format: :short))
    end

    it "reads the latest snapshot of each dossier, not an older one" do
      snap(acme, taken_on: Date.current - 3, overdue_receivables: BigDecimal("999.99"))
      sign_in alice
      get portfolio_path
      expect(response.body).to include("111.11").and not_include("999.99")
    end
  end

  describe "filters and sorts" do
    before do
      acme.update!(responsible: alice)
      snap(acme, closing_status: "in_progress", closing_progress: 40, closing_year: 2026, next_vat_due_on: Date.current - 2, vat_overdue: true, blocking_count: 3, warning_count: 0)
      snap(bakery, closing_status: "open", closing_year: 2026, next_vat_due_on: Date.current + 10, blocking_count: 0, warning_count: 2, unreconciled_bank_lines: 9)
      sign_in alice
    end

    def names = Nokogiri::HTML(response.body).css("tr[data-entity] td:nth-child(2)").map { |td| td.children.first.text.strip }

    it "filters by closing, VAT, severity and the person in charge" do
      get portfolio_path, params: { closing: "in_progress" }
      expect(names).to eq([ "Acme Fiduciary" ])
      get portfolio_path, params: { vat: "overdue" }
      expect(names).to eq([ "Acme Fiduciary" ])
      get portfolio_path, params: { vat: "soon" }
      expect(names).to eq([ "Acme Fiduciary", "Bakery Shared" ]) # an overdue return is also due within 30 days
      get portfolio_path, params: { severity: "blocking" }
      expect(names).to eq([ "Acme Fiduciary" ])
      get portfolio_path, params: { severity: "warnings" }
      expect(names).to eq([ "Bakery Shared" ])
      get portfolio_path, params: { responsible: "me" }
      expect(names).to eq([ "Acme Fiduciary" ])
    end

    it "sorts, by name by default and by what the column says" do
      get portfolio_path
      expect(names).to eq([ "Acme Fiduciary", "Bakery Shared" ])
      get portfolio_path, params: { sort: "bank" }
      expect(names).to eq([ "Bakery Shared", "Acme Fiduciary" ])
      get portfolio_path, params: { sort: "blocking" }
      expect(names).to eq([ "Acme Fiduciary", "Bakery Shared" ])
    end

    it "filters by organization" do
      group = Organization.create!(name: "Firm")
      OrganizationMembership.create!(organization: group, user: alice, role: "owner")
      bakery.update!(organization: group)
      get portfolio_path, params: { organization_id: group.id }
      expect(names).to eq([ "Bakery Shared" ])
    end
  end

  describe "grouped actions: no accounting entry" do
    before do
      snap(acme)
      snap(bakery)
      sign_in alice # owner of Acme, accountant in Bakery
    end

    it "runs the checks where the person may, and leaves out the dossier where they may not" do
      expect { post portfolio_bulk_path, params: { bulk_action: "run_checks", entity_ids: [ acme.id, bakery.id, cafe.id ] } }
        .to have_enqueued_job(Portfolio::RunChecksJob).with(acme.id).and have_enqueued_job(Portfolio::RunChecksJob).with(bakery.id)
      expect(flash[:notice]).to include("2 dossiers done", "1 left out") # Cafe: not hers
      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: "portfolio_run_checks").pluck(:entity_id) }).to match_array([ acme.id, bakery.id ])
    end

    it "asks for a backup only where the person is owner" do
      expect { post portfolio_bulk_path, params: { bulk_action: "export", entity_ids: [ acme.id, bakery.id ] } }.to have_enqueued_job(Exports::BackupJob).once
      expect(ActsAsTenant.without_tenant { DataExport.pluck(:entity_id) }).to eq([ acme.id ])
    end

    it "notifies the person in charge, or the owners when nobody is" do
      bob_in_acme = create(:user, full_name: "Carol")
      create(:user_entity, :accountant, user: bob_in_acme, entity: acme)
      acme.update!(responsible: bob_in_acme)
      post portfolio_bulk_path, params: { bulk_action: "notify", entity_ids: [ acme.id, bakery.id ], message: "Please file the VAT return" }

      notes = ActsAsTenant.without_tenant { Accounting::Notification.order(:id).to_a }
      expect(notes.map { |n| [ n.entity_id, n.user_id ] }).to match_array([ [ acme.id, bob_in_acme.id ], [ bakery.id, bob.id ] ])
      expect(notes.first.data).to include("message" => "Please file the VAT return", "by" => "Alice Accountant")
    end

    it "writes no accounting entry whatever the action" do
      ActsAsTenant.with_tenant(acme) { create(:journal_entry, :draft, journal: create(:journal), fiscal_year: create(:fiscal_year, entity: acme), entry_date: Date.current) }
      %w[run_checks notify export].each do |action|
        post portfolio_bulk_path, params: { bulk_action: action, entity_ids: [ acme.id ], message: "x" }
      end
      expect(ActsAsTenant.without_tenant { Accounting::JournalEntry.count }).to eq(1)
    end

    it "asks for an action, a dossier and, to notify, a message" do
      post portfolio_bulk_path, params: { entity_ids: [ acme.id ] }
      expect(flash[:alert]).to eq("Choose an action.")
      post portfolio_bulk_path, params: { bulk_action: "run_checks" }
      expect(flash[:alert]).to eq("Choose at least one dossier.")
      post portfolio_bulk_path, params: { bulk_action: "notify", entity_ids: [ acme.id ] }
      expect(flash[:alert]).to eq("Write the message to send.")
    end
  end

  describe "the person in charge" do
    it "is named by the owner of the dossier, among the people who work in it" do
      sign_in alice
      patch portfolio_responsible_path(acme), params: { responsible_id: alice.id }
      expect(acme.reload.responsible).to eq(alice)
      expect(ActsAsTenant.without_tenant { Accounting::AuditLog.where(action: "responsible_changed").last.payload }).to include("responsible" => alice.email)

      patch portfolio_responsible_path(acme), params: { responsible_id: bob.id } # Bob does not work in Acme
      expect(response).to have_http_status(:not_found)
      expect(acme.reload.responsible).to eq(alice)
    end

    it "is not changed by someone who is not the owner" do
      sign_in alice
      patch portfolio_responsible_path(bakery), params: { responsible_id: alice.id }
      expect(flash[:alert]).to match(/Only the owner/)
      expect(bakery.reload.responsible).to be_nil
    end
  end

  describe "the snapshots" do
    it "are recalculated on demand, one job per dossier of the portfolio" do
      sign_in alice
      expect { post portfolio_refresh_path }.to have_enqueued_job(Portfolio::SnapshotJob).with(acme.id).and have_enqueued_job(Portfolio::SnapshotJob).with(bakery.id)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |j| j["arguments"] }.flatten).not_to include(cafe.id)
    end

    it "are written every night for the dossiers that turned the feature on, each in its own books" do
      cafe.update!(features: { "f12" => false })
      Portfolio::SnapshotAllJob.perform_now
      queued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j["job_class"] == "Portfolio::SnapshotJob" }.flat_map { |j| j["arguments"] }
      expect(queued).to include(acme.id, bakery.id) # (entities that earlier specs left behind are in the list too: the suite truncates only at its start)
      expect(queued).not_to include(cafe.id)
      Portfolio::SnapshotJob.perform_now(acme.id)
      Portfolio::SnapshotJob.perform_now(cafe.id) # flag off: nothing
      expect(DossierHealthSnapshot.pluck(:entity_id)).to eq([ acme.id ])
    end

    it "run the checks of the dossier and refresh its snapshot when asked from the portfolio" do
      Portfolio::RunChecksJob.perform_now(acme.id)
      expect(ActsAsTenant.with_tenant(acme) { Accounting::ConsistencyRun.where(trigger: "portfolio").count }).to eq(1)
      expect(DossierHealthSnapshot.find_by(entity: acme).blocking_count).not_to be_nil
    end
  end

  describe "the dossier selector" do
    it "changes in one click, and the last dossier is where the next session starts" do
      sign_in alice
      get accounting_root_path
      expect(response.body).to include("entity-switcher")

      post switch_entity_path(bakery)
      expect(alice.reload.last_entity_id).to eq(bakery.id)

      delete destroy_user_session_path
      sign_in alice
      get accounting_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bakery Shared")
    end
  end
end

require "rails_helper"

# F01: Reader and External auditor read on screen; they download only if the entity allows it.
RSpec.describe "Exporting as a read-only role", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)  { create(:user, role: :admin) }
  let(:reader) { create(:user, role: :auditor) }
  let(:external_auditor) { create(:user, role: :auditor) }
  let!(:owner_membership)   { create(:user_entity, :admin,   user: owner,            entity: entity) }
  let!(:reader_membership)  { create(:user_entity, :manager, user: reader,           entity: entity) }
  let!(:auditor_membership) { create(:user_entity, :auditor, user: external_auditor, entity: entity) }

  { "a reader" => :reader, "an external auditor" => :external_auditor }.each do |label, who|
    context "as #{label}" do
      let(:person) { public_send(who) }

      before { sign_in person }

      it "reads the report on screen" do
        get accounting_reports_trial_balance_path

        expect(response).to have_http_status(:ok)
      end

      %i[csv xlsx pdf].each do |format|
        it "cannot download it as #{format} while the entity does not allow it" do
          get accounting_reports_trial_balance_path(format: format)

          expect(response).to have_http_status(:redirect)
        end
      end

      it "can download it once the owner allows read-only exports" do
        entity.update!(read_only_export: true)

        get accounting_reports_trial_balance_path(format: :csv)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/csv")
      end

      it "downloads nothing again once the owner takes the permission back" do
        entity.update!(read_only_export: true)
        entity.update!(read_only_export: false)

        get accounting_reports_trial_balance_path(format: :csv)

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  context "the closing bundle, for the external auditor" do
    before { sign_in external_auditor }

    it "opens the page" do
      get accounting_closing_bundle_path(fiscal_year_id: fiscal_year.id)

      expect(response).to have_http_status(:ok)
    end

    it "refuses the download while exports are off, and gives it once they are on" do
      get bundle_accounting_closing_bundle_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:redirect)

      entity.update!(read_only_export: true)
      get bundle_accounting_closing_bundle_path(fiscal_year_id: fiscal_year.id)
      expect(response).to have_http_status(:ok)
    end
  end

  it "does not offer the reader the audit trail (capability table: owner, accountant, external auditor)" do
    sign_in reader

    get accounting_audit_logs_path

    expect(response).to have_http_status(:redirect)
  end

  describe "the owner's switch" do
    before { sign_in owner }

    it "allows read-only exports from the entity settings" do
      get edit_accounting_settings_entity_path
      expect(response.body).to include("entity[read_only_export]")

      patch accounting_settings_entity_path, params: { entity: { read_only_export: "1" } }

      expect(entity.reload.read_only_export).to be true
    end

    it "ignores an accountant who sends it" do
      accountant = create(:user, role: :accountant)
      create(:user_entity, :accountant, user: accountant, entity: entity)
      sign_out owner
      sign_in accountant

      patch accounting_settings_entity_path, params: { entity: { read_only_export: "1" } }

      expect(entity.reload.read_only_export).to be false
    end
  end

  describe "the external auditor's PDFs carry their name (F01)" do
    before { entity.update!(read_only_export: true) }

    it "watermarks a report downloaded by an external auditor" do
      sign_in external_auditor

      get accounting_reports_trial_balance_path(format: :pdf)

      expect(watermarked_on_every_page?(response.body, external_auditor.full_name)).to be true
    end

    it "does not watermark a reader's or an owner's download" do
      sign_in reader
      get accounting_reports_trial_balance_path(format: :pdf)
      expect(watermarked_on_no_page?(response.body, reader.full_name)).to be true

      sign_out reader
      sign_in owner
      get accounting_reports_trial_balance_path(format: :pdf)
      expect(watermarked_on_no_page?(response.body, owner.full_name)).to be true
    end

    it "watermarks every PDF of the closing bundle they download" do
      sign_in external_auditor

      get bundle_accounting_closing_bundle_path(fiscal_year_id: fiscal_year.id)

      pdfs = Accounting::Zipper.read(response.body).select { |name, _| name.end_with?(".pdf") }
      expect(pdfs).not_to be_empty
      expect(pdfs.values.map { |bytes| watermarked_on_every_page?(bytes, external_auditor.full_name) }).to all(be true)
    end
  end
end

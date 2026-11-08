require "rails_helper"

RSpec.describe Settings::SidebarComponent, type: :component do
  let(:admin) { build_stubbed(:user, role: :admin) }

  before { signed_in = admin; vc_test_controller.define_singleton_method(:current_user) { signed_in } }

  it "renders all four settings sections" do
    render_inline(described_class.new(current_path: "/accounting/settings"))
    expect(page).to have_text("Journals")
    expect(page).to have_text("Bank Accounts")
    expect(page).to have_text("Chart of Accounts")
    expect(page).to have_text("Analytical Accounts")
  end

  it "highlights the active section" do
    render_inline(described_class.new(current_path: "/accounting/settings/journals"))
    expect(page).to have_css("a.bg-primary-50", text: "Journals")
  end

  it "renders a back link to the main app" do
    render_inline(described_class.new(current_path: "/accounting/settings"))
    expect(page).to have_link("Back to LedgerFlow")
  end

  describe "API Clients and Webhooks links" do
    include_context "with entity"

    let(:user) { create(:user, role: :accountant) } # global role is not an owner's
    let(:render_sidebar) { render_inline(described_class.new(current_path: "/accounting/settings")) }

    before do
      entity.update!(budgetflow_enabled: true, features: { "f13" => true })
      signed_in = user
      vc_test_controller.define_singleton_method(:current_user) { signed_in }
      vc_test_controller.define_singleton_method(:budgetflow_enabled?) { true }
      vc_test_controller.define_singleton_method(:feature?) { |_| true }
    end

    it "shows them to an owner of the entity, whatever the account's global role" do
      create(:user_entity, user: user, entity: entity, role: :admin)
      render_sidebar
      expect(page).to have_link("API Clients")
      expect(page).to have_link("Webhooks")
    end

    it "hides them from a member who may not delete" do
      create(:user_entity, user: user, entity: entity, role: :assistant)
      render_sidebar
      expect(page).not_to have_link("API Clients")
      expect(page).not_to have_link("Webhooks")
    end
  end
end

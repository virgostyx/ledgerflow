require "rails_helper"

RSpec.describe Settings::SidebarComponent, type: :component do
  let(:admin) { build_stubbed(:user, role: :admin) }

  before { allow(vc_test_controller).to receive(:current_user).and_return(admin) }

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
end

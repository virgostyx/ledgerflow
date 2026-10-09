require "rails_helper"

# B01a §4 "Mobile": the application is usable on a phone - the menu folds away behind a button, and the screens where an approver works do not
# scroll sideways. A phone is 390 px wide.
RSpec.describe "Approving from a phone", type: :system, js: true do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:owner) { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let!(:policy) do
    Approvals::Policy.create!(name: "all", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
    end
  end
  let!(:request_record) do
    invoice = create(:invoice, :supplier, fiscal_year: fiscal_year, partner: create(:partner, name: "A Rather Long Supplier Name And Co Ltd")).tap do |i|
      create(:invoice_line, invoice: i, account: create(:account), unit_price: "1000.00", description: "Consulting services for the month of October, all included")
    end
    Approvals::Submit.call(invoice: invoice, user: nil)[:request]
  end

  before do
    page.driver.browser.manage.window.resize_to(390, 800)
    login_as owner, scope: :user
  end

  def sideways_scroll? = page.evaluate_script("document.documentElement.scrollWidth > window.innerWidth")

  # the menu slides in and out over 150 ms: wait for it to be where it is going
  def menu_shown?(wanted)
    page.document.synchronize { raise Capybara::ExpectationNotMet, "menu #{wanted ? 'not' : 'still'} in view" unless menu_in_view? == wanted }
    true
  end

  def menu_in_view? = page.evaluate_script("(() => { const r = document.querySelector('aside').getBoundingClientRect(); return r.right > 0 && r.left < window.innerWidth })()")

  it "folds the menu away behind a button, and opens it over the page" do
    visit accounting_approvals_path

    expect(page).to have_button("Menu")
    expect(menu_shown?(false)).to be true

    click_button "Menu"
    expect(menu_shown?(true)).to be true
    expect(page).to have_link("To approve")

    click_button "Close menu"
    expect(menu_shown?(false)).to be true
  end

  it "does not scroll sideways in the list, nor on the invoice, and has its buttons within reach" do
    visit accounting_approvals_path
    expect(page).to have_text("A Rather Long Supplier Name And Co Ltd")
    expect(sideways_scroll?).to be false

    click_link "Review"
    expect(page).to have_button("Approve")
    expect(sideways_scroll?).to be false
    expect(page.evaluate_script("document.querySelector('button[value=approved]').getBoundingClientRect().right <= window.innerWidth")).to be true
  end

  it "keeps the floating tools (calculator, converter, music) off a phone, where they would sit on the amounts" do
    visit accounting_approvals_path

    expect(page).to have_no_css("[data-controller='calculator']", visible: :visible)
    expect(page).to have_no_css("[data-controller='currency-converter']", visible: :visible)
    expect(page).to have_no_css("[data-controller='music-player']", visible: :visible)
  end

  it "leaves the desktop as it was: the menu is there without a button, and the tools" do
    page.driver.browser.manage.window.resize_to(1280, 800)
    visit accounting_approvals_path

    expect(menu_shown?(true)).to be true
    expect(page).to have_no_button("Menu")
    expect(page).to have_css("[data-controller='calculator']", visible: :visible)
  end
end

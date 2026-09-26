require 'rails_helper'

RSpec.describe 'Collapsible sidebar', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    page.driver.browser.manage.window.resize_to(1280, 500) # a low window, like a laptop
    login_as accountant, scope: :user
  end

  def sign_out_in_viewport?
    page.evaluate_script(<<~JS)
      (() => { const r = [...document.querySelectorAll('aside button')].find(b => b.textContent.includes('Sign out')).getBoundingClientRect();
               return r.top >= 0 && r.bottom <= window.innerHeight })()
    JS
  end

  it 'keeps Sign out inside the window without scrolling the page, even with every section open' do
    visit accounting_root_path
    expect(page).to have_css('aside details[open]', minimum: 1)
    expect(sign_out_in_viewport?).to be true
  end

  it 'collapses a section by its header, and remembers it on the next page' do
    visit accounting_root_path
    expect(page).to have_link('Trial Balance')

    find('aside summary', text: /reports/i).click
    expect(page).to have_no_link('Trial Balance', visible: true)

    visit accounting_journal_entries_path
    expect(page).to have_no_link('Trial Balance', visible: true)
    expect(page).to have_link('Journal Entries')
  end

  it 'keeps the section of the current page open even if it was collapsed' do
    visit accounting_root_path
    find('aside summary', text: /reports/i).click
    visit accounting_reports_trial_balance_path

    expect(page).to have_link('Trial Balance')
  end
end

require 'rails_helper'

RSpec.describe 'Workflow : Création et validation d une écriture', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:account_604) { create(:account, code: '604000', label_fr: 'Services divers') }
  let!(:account_440) { create(:account, code: '440000', label_fr: 'Fournisseurs') }
  let!(:account_411) { create(:account, code: '411000', label_fr: 'TVA à récupérer') }
  let(:accountant)   { create(:user, role: :accountant) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { login_as accountant, scope: :user }

  it 'permet à un comptable de créer et valider une écriture équilibrée' do
    visit new_accounting_journal_entry_path

    select 'ACH — Achats', from: 'Journal'
    execute_script("document.querySelector('input[type=\"date\"]').value = '#{Date.current.iso8601}'")
    fill_in 'Description', with: 'Achat fournitures bureau'

    within '[data-controller="journal-entry-form"]' do
      within '.entry-lines', match: :first do
        execute_script(
          "document.querySelector('[name=\"accounting_journal_entry[lines_attributes][0][account_id]\"]').value = '#{account_604.id}'"
        )
        fill_in 'Debit', with: '1210.00'
      end

      click_button 'Add a line'
      expect(page).to have_css('.entry-lines', count: 2)

      execute_script(
        "document.querySelectorAll('.entry-lines')[1].querySelector('[name*=\"account_id\"]').value = '#{account_440.id}'"
      )
      within all('.entry-lines').last do
        fill_in 'Credit', with: '1210.00'
      end
    end

    expect(page).to have_css('.balance-indicator .bg-emerald-100', text: 'Balanced')
    expect(page).to have_button('Post entry', disabled: false)

    click_button 'Post entry'

    expect(page).to have_css('.bg-emerald-100', text: 'Posted')
    expect(page).not_to have_button('Edit')
  end

  it 'désactive le bouton Valider quand l écriture est déséquilibrée' do
    visit new_accounting_journal_entry_path

    within '[data-controller="journal-entry-form"]' do
      within '.entry-lines', match: :first do
        fill_in 'Debit', with: '500.00'
      end
    end

    expect(page).to have_css('.balance-indicator .bg-amber-100', text: 'Unbalanced')
    expect(page).to have_button('Post entry', disabled: true)
  end

  it 'shows the totals and says why Save is disabled' do
    visit new_accounting_journal_entry_path

    within '[data-controller="journal-entry-form"]' do
      within '.entry-lines', match: :first do
        fill_in 'Debit', with: '500.00'
      end
    end

    expect(page).to have_css('[data-journal-entry-form-target=totalDebit]', text: '500.00')
    expect(page).to have_css('[data-journal-entry-form-target=totalCredit]', text: '0.00')
    expect(page).to have_css('.balance-indicator', text: 'Debit exceeds credit by 500.00')
  end

  it 'leaves a removed saved line out of the totals' do
    entry = create(:journal_entry, :draft, journal: purchase_journal, fiscal_year: fiscal_year)
    # A JS system spec runs outside the test transaction: the double-entry check must see both lines at commit.
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal('1000.00'), credit: BigDecimal('0'))
      create(:journal_entry_line, journal_entry: entry, account: account_440, debit: BigDecimal('0'), credit: BigDecimal('1000.00'))
    end
    visit edit_accounting_journal_entry_path(entry)

    expect(page).to have_css('[data-journal-entry-form-target=totalDebit]', text: '1,000.00')
    expect(page).to have_css('.balance-indicator', text: 'Balanced')

    within(all('.entry-lines').last) { find('button', text: '×').click }

    expect(page).to have_css('.balance-indicator', text: 'Debit exceeds credit by 1,000.00')
    expect(page).to have_button('Save as draft', disabled: true)
  end

  it 'opens the analytics when the chosen account requires an axis' do
    axis = create(:analytical_axis, :proj, required_for_account_classes: [ account_604.account_class ])
    create(:analytical_account, analytical_axis: axis, code: 'PROJ-001', label_fr: 'Project Alpha')
    visit new_accounting_journal_entry_path

    within(all('.entry-lines').first) do
      expect(page).to have_css('details.line-extras:not([open])', visible: :all)
      find('input[data-account-search-target=input]').fill_in(with: '604')
      find('[data-account-search-target=suggestion]', text: '604000').click
      expect(page).to have_css('details.line-extras[open]')
      expect(page).to have_content('required')
    end
  end

  describe 'keyboard entry' do
    before { visit new_accounting_journal_entry_path }

    def account_input(index) = all('.entry-lines')[index].find('input[data-account-search-target=input]')

    it 'puts the focus on the new line and pre-fills the amount still missing' do
      fill_in_first_line_debit('500.00')
      click_button 'Add a line'

      expect(page).to have_css('.entry-lines', count: 2)
      expect(evaluate_script("document.activeElement === document.querySelectorAll('.entry-lines')[1].querySelector('input[data-account-search-target=input]')")).to be(true)
      within(all('.entry-lines')[1]) { expect(page).to have_field('Credit', with: '500.00') }
      expect(page).to have_css('.balance-indicator', text: 'Balanced')
    end

    it 'adds a line on Ctrl+Enter, without saving the entry' do
      fill_in_first_line_debit('500.00')
      find('.entry-lines input[name$="[debit]"]', match: :first).send_keys([ :control, :enter ])

      expect(page).to have_css('.entry-lines', count: 2)
      expect(page).to have_current_path(new_accounting_journal_entry_path)
    end

    it 'chooses an account with the arrow keys and Enter, and shows its name' do
      account_input(0).send_keys('604', :down, :enter)

      expect(account_input(0).value).to eq('604000 — Services divers')
      expect(first('input[name$="[account_id]"]', visible: :all).value).to eq(account_604.id.to_s)
      expect(page).to have_current_path(new_accounting_journal_entry_path)
    end

    it 'takes an exact account code typed then Tab' do
      account_input(0).send_keys('440000', :tab)

      expect(first('input[name$="[account_id]"]', visible: :all).value).to eq(account_440.id.to_s)
      expect(account_input(0).value).to eq('440000 — Fournisseurs')
    end

    it 'forgets the account when the text is edited afterwards, so a stale account is never saved' do
      account_input(0).send_keys('604', :down, :enter)
      account_input(0).send_keys(:backspace)

      expect(first('input[name$="[account_id]"]', visible: :all).value).to eq('')
    end

    it 'exposes the account field as a combobox' do
      expect(page).to have_css('input[data-account-search-target=input][role=combobox][aria-expanded=false]', count: 1)
      account_input(0).send_keys('604')
      expect(page).to have_css('input[role=combobox][aria-expanded=true]')
      expect(page).to have_css('[role=listbox] [role=option]', text: '604000')
    end

    def fill_in_first_line_debit(amount)
      within(all('.entry-lines').first) { fill_in 'Debit', with: amount }
    end
  end

  describe 'on a phone (390px)' do
    before do
      page.driver.browser.manage.window.resize_to(390, 800)
      visit new_accounting_journal_entry_path
      click_button 'Refuse' if page.has_button?('Refuse', wait: 1)
    end

    after { page.driver.browser.manage.window.resize_to(1400, 1000) }

    def width_of(selector) = evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().width")

    it 'does not scroll sideways' do
      expect(evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    end

    it 'gives the account the full width of the line, and each amount room for its digits' do
      expect(width_of('.entry-lines input[data-account-search-target=input]')).to be >= 280
      expect(width_of('.entry-lines input[name$="[debit]"]')).to be >= 120
      expect(width_of('.entry-lines input[name$="[credit]"]')).to be >= 120
    end

    it 'labels the amounts in the line instead of in a detached header' do
      expect(page).to have_no_css('.entry-columns', visible: :visible)
      %w[debit credit].each do |side|
        # An sr-only label is 1px wide: a label a person can read is wider than that.
        expect(evaluate_script("document.querySelector('.entry-lines label[for$=#{side}]').getBoundingClientRect().width")).to be >= 20
      end
    end

    it 'has touch targets of at least 44px for remove and Save' do
      expect(evaluate_script("document.querySelector('.entry-lines button[aria-label=\"Remove line\"]').getBoundingClientRect().height")).to be >= 44
      expect(evaluate_script("document.querySelector('.entry-totals-bar input[type=submit]').getBoundingClientRect().height")).to be >= 44
    end

    it 'keeps the totals bar to a fraction of the screen' do
      expect(evaluate_script("document.querySelector('.entry-totals-bar').getBoundingClientRect().height")).to be <= 170
    end
  end

  describe 'on a tablet (768px, sidebar visible)' do
    before do
      page.driver.browser.manage.window.resize_to(768, 900)
      visit new_accounting_journal_entry_path
      click_button 'Refuse' if page.has_button?('Refuse', wait: 1)
    end

    after { page.driver.browser.manage.window.resize_to(1400, 1000) }

    it 'keeps the account and the amounts readable' do
      width = ->(sel) { evaluate_script("document.querySelector(#{sel.to_json}).getBoundingClientRect().width") }
      expect(width.call('.entry-lines input[data-account-search-target=input]')).to be >= 250
      expect(width.call('.entry-lines input[name$="[debit]"]')).to be >= 100
      expect(evaluate_script('document.documentElement.scrollWidth <= window.innerWidth')).to be(true)
    end
  end

  describe 'hardened entry' do
    let!(:axis) { create(:analytical_axis, :proj, required_for_account_classes: [ account_604.account_class ]) }
    let!(:project) { create(:analytical_account, analytical_axis: axis, code: 'P1', label_fr: 'Project Alpha') }

    before { visit new_accounting_journal_entry_path }

    def choose_account(index, code)
      all('.entry-lines')[index].find('input[data-account-search-target=input]').send_keys(code, :down, :enter)
    end

    def amount(index, side, value)
      within(all('.entry-lines')[index]) { fill_in side, with: value }
    end

    it 'keeps debit and credit exclusive on one line' do
      amount(0, 'Debit', '100.00')
      amount(0, 'Credit', '40.00')

      within(all('.entry-lines').first) { expect(page).to have_field('Debit', with: '0.00') }
      expect(page).to have_css('[data-journal-entry-form-target=totalCredit]', text: '40.00')
    end

    it 'removes a line with an undo, and the removed line is not submitted meanwhile' do
      click_button 'Add a line'
      expect(page).to have_css('.entry-lines', count: 2)

      within(all('.entry-lines').last) { click_button 'Remove line' }

      expect(page).to have_css('[data-journal-entry-form-target=undoNotice]', text: 'Line removed', visible: :visible)
      expect(page).to have_css('.entry-lines input[name$="[debit]"]:disabled', visible: :all, count: 1)
      click_button 'Undo'
      expect(page).to have_css('.entry-lines', count: 2, visible: :visible)
      expect(page).to have_no_css('.entry-lines input:disabled', visible: :all)
    end

    it 'moves the focus to the neighbouring line after a removal' do
      click_button 'Add a line'
      within(all('.entry-lines').last) { click_button 'Remove line' }

      expect(evaluate_script("document.activeElement === document.querySelectorAll('.entry-lines')[0].querySelector('input[data-account-search-target=input]')")).to be(true)
    end

    it 'says so when no account matches, and flags a typed account that was never chosen' do
      input = all('.entry-lines').first.find('input[data-account-search-target=input]')
      input.send_keys('zzz')
      expect(page).to have_css('[role=listbox] [role=option]', text: 'No account matches')

      find('body').click
      expect(page).to have_css('input[data-account-search-target=input][aria-invalid=true]')
      expect(page).to have_css('[data-account-search-target=error]', text: 'Choose an account from the list', visible: :visible)
    end

    it 'keeps Save closed while a balanced line has no account, and says which' do
      amount(0, 'Debit', '500.00')
      click_button 'Add a line'

      expect(page).to have_css('.balance-indicator', text: 'Balanced')
      expect(page).to have_css('.balance-indicator', text: '2 lines need an account')
      expect(page).to have_button('Post entry', disabled: true)
    end

    it 'keeps Save closed until the required analytic account is chosen' do
      choose_account(0, '604')
      amount(0, 'Debit', '500.00')
      click_button 'Add a line'
      choose_account(1, '440')
      all('.entry-lines')[1].find('details.line-extras')

      expect(page).to have_css('.balance-indicator', text: 'need a required analytic account')
      expect(page).to have_button('Post entry', disabled: true)

      all('.entry-lines').each { |line| line.find('select[data-axis-id]').select('Project Alpha') }
      expect(page).to have_button('Post entry', disabled: false)
    end

    it 'announces a change of state, not every keystroke' do
      amount(0, 'Debit', '1')
      before_text = find('[data-journal-entry-form-target=balanceAnnouncer]', visible: :all).text(:all)
      amount(0, 'Debit', '12')
      expect(find('[data-journal-entry-form-target=balanceAnnouncer]', visible: :all).text(:all)).to eq(before_text)
    end
  end

  describe 'wording' do
    before { visit new_accounting_journal_entry_path }

    it 'names the action for its effect: an accountant who may post sees Post entry, with its consequence' do
      expect(page).to have_button('Post entry', disabled: true)
      expect(page).to have_css('#entry-save-consequence', text: 'records the entry permanently', visible: :all)
    end

    it 'does not scold while the entry is being typed: the gap is amber, never red, and said once' do
      within(all('.entry-lines').first) { fill_in 'Debit', with: '500.00' }

      expect(page).to have_css('.balance-indicator .bg-amber-100', text: 'Unbalanced')
      expect(page).to have_no_css('.balance-indicator .bg-red-100')
      expect(page).to have_no_content('Save is available once debit equals credit')
    end

    it 'leaves a clean form at once, and asks before discarding what was typed' do
      within(all('.entry-lines').first) { fill_in 'Debit', with: '500.00' }

      click_link 'Cancel'
      expect(page).to have_link('Discard this entry?')
      expect(page).to have_current_path(new_accounting_journal_entry_path)

      click_link 'Discard this entry?'
      expect(page).to have_current_path(accounting_journal_entries_path)
    end

    it 'cancels straight away when nothing was typed' do
      click_link 'Cancel'
      expect(page).to have_current_path(accounting_journal_entries_path)
    end
  end
end

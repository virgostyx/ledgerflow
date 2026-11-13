require 'rails_helper'

RSpec.describe Layouts::JournalEntryFormComponent, type: :component do
  include_context 'with_open_fiscal_year'

  let(:journals) { [ create(:journal, :purchase), create(:journal, :sale) ] }
  let(:accounts) { [ create(:account, code: '604000', label_fr: 'Services divers') ] }
  let(:entry)    { build(:journal_entry, journal: journals.first, fiscal_year: fiscal_year) }

  let!(:supplier)          { create(:partner, :supplier, name: 'Acme Supplies') }
  let!(:inactive_partner)  { create(:partner, :inactive, name: 'Dormant SA') }

  before { render_inline(described_class.new(entry: entry, journals: journals, accounts: accounts)) }

  describe 'partner per line' do
    it 'renders a partner select on the first line' do
      expect(page).to have_select('accounting_journal_entry[lines_attributes][0][partner_id]', with_options: [ 'Acme Supplies' ])
    end

    it 'lists active partners only' do
      expect(page).not_to have_css('option', text: 'Dormant SA', visible: :all)
    end

    it 'renders a partner select in the new line template' do
      # Capybara's parser does not expose <template> content, so check the rendered markup.
      expect(rendered_content).to include('lines_attributes][NEW_INDEX][partner_id]')
    end
  end

  it 'a le data-controller journal-entry-form' do
    expect(page).to have_css('[data-controller="journal-entry-form"]')
  end

  it 'affiche un select pour le journal' do
    expect(page).to have_select('Journal')
  end

  it 'affiche un champ date' do
    expect(page).to have_field('Date')
  end

  it 'affiche la zone de lignes d écriture' do
    expect(page).to have_css('.entry-lines')
  end

  it 'affiche l indicateur de balance' do
    expect(page).to have_css('.balance-indicator')
  end

  describe 'totals bar' do
    it 'shows the debit and credit totals in a bar that also holds Save' do
      expect(page).to have_css('.entry-totals-bar', text: 'Total debit')
      expect(page).to have_css('.entry-totals-bar', text: 'Total credit')
      expect(page).to have_css('.entry-totals-bar input[type=submit][value="Save as draft"]')
    end

    it 'keeps the bar in view while the lines scroll' do
      expect(page).to have_css('.entry-totals-bar.sticky.bottom-0')
    end

    it 'announces only changes of balance state, through its own polite region' do
      expect(page).to have_css('.entry-totals-bar [aria-live=polite][data-journal-entry-form-target=balanceAnnouncer]', visible: :all)
      expect(page).to have_no_css('.balance-indicator[aria-live], .balance-indicator[role=status]', visible: :all)
    end

    it 'has a region for the undo notice of a removed line' do
      expect(page).to have_css('[data-journal-entry-form-target=undoNotice][aria-live=polite]', visible: :all)
    end

    it 'ties Save to the balance status, so a disabled Save has a stated reason' do
      ids = page.find('.entry-totals-bar input[type=submit]', visible: :all)['aria-describedby'].split
      expect(ids).to include('entry-balance-status')
      ids.each { |id| expect(page).to have_css("##{id}", visible: :all) }
    end
  end

  describe 'one row per line, with the rare fields behind a disclosure' do
    it 'folds currency and analytics into a closed details on a plain line' do
      expect(page).to have_css('.entry-lines details.line-extras:not([open])', visible: :all)
      expect(page).to have_css('.entry-lines details.line-extras summary', text: 'Currency & analytics')
    end

    it 'keeps the currency fields in the markup, inside the disclosure' do
      expect(page).to have_css('.line-extras select[name$="[currency]"]', visible: :all)
      expect(page).to have_css('.line-extras input[name$="[amount_currency]"]', visible: :all)
    end

    it 'builds the new-line template from the same markup as the first line' do
      expect(rendered_content).to include('lines_attributes][NEW_INDEX][currency]')
      expect(rendered_content.scan('line-extras').size).to be >= 2
    end

    it 'does not use the brand colour as zebra decoration' do
      expect(rendered_content).not_to include('odd:bg-primary-50')
    end
  end

  describe 'on a narrow screen (below 1024px)' do
    it 'hides the column headers, because each field is labelled in its own card' do
      expect(page).to have_css('.entry-columns.hidden.lg\\:grid', visible: :all)
    end

    it 'shows each line as a two-column card below lg, and as one row from lg' do
      expect(page).to have_css('.entry-lines > div.grid.grid-cols-2.lg\\:grid-cols-12')
    end

    it 'gives Debit and Credit a visible label below lg' do
      expect(page).to have_css('.entry-lines label.lg\\:sr-only', text: 'Debit')
      expect(page).to have_css('.entry-lines label.lg\\:sr-only', text: 'Credit')
    end

    it 'gives the remove button a 44px touch target' do
      expect(page).to have_css('.entry-lines button[aria-label="Remove line"].min-h-11.min-w-11')
    end

    it 'folds the totals bar into two columns below lg' do
      expect(page).to have_css('.entry-totals-bar .grid.grid-cols-2.lg\\:grid-cols-12')
    end
  end

  describe 'chart of accounts' do
    it 'is sent once for the whole form, not once per line and again for the template' do
      expect(rendered_content.scan('"label":"Services divers"').size).to eq(1)
      expect(page).to have_css('script#journal-entry-accounts[type="application/json"]', visible: :all)
    end

    it 'is read by every line from that one copy' do
      expect(page).to have_css('.entry-lines [data-account-search-source-id-value="journal-entry-accounts"]')
      expect(page).to have_no_css('[data-account-search-accounts-value]', visible: :all)
    end
  end

  describe 'header' do
    it 'gives the description two columns, as the field read most often later' do
      expect(page).to have_css('.col-span-2 input[name$="[description]"]')
    end

    it 'uses the same field style as the lines, with a persistent label above' do
      line_class = page.find('.entry-lines input[name$="[label]"]')[:class]
      %w[journal_id entry_date description].each do |name|
        field = page.find("[name$='[#{name}]']")
        expect(field[:class]).to eq(line_class).or include('rounded-md')
      end
      expect(rendered_content).not_to include('lf-floating-label')
      expect(page).to have_css('label[for$=journal_id]', text: 'Journal')
    end

    it 'folds the rarely used reversal date away, with a visible explanation instead of a tooltip' do
      expect(page).to have_css('details.header-more:not([open])', visible: :all)
      expect(page).to have_css('details.header-more summary', text: 'More options')
      expect(page).to have_css('details.header-more', text: 'A draft reversal of this entry is prepared on that date', visible: :all)
      expect(page).to have_no_css('[name$="[auto_reverse_on]"][title]', visible: :all)
    end

    context 'when a reversal date is already set' do
      let(:entry) do
        build(:journal_entry, journal: journals.first, fiscal_year: fiscal_year, auto_reverse_on: Date.current + 30)
      end

      it 'opens the options so the date is not hidden' do
        expect(page).to have_css('details.header-more[open]', visible: :all)
      end
    end
  end

  describe 'wording of the commit' do
    it 'says it saves a draft by default, and what a draft allows' do
      expect(page).to have_button('Save as draft', disabled: true)
      expect(page).to have_css('#entry-save-consequence', text: 'A draft can be edited until it is validated', visible: :all)
    end

    context 'when the person may post the entry' do
      before { render_inline(described_class.new(entry: entry, journals: journals, accounts: accounts, posting: true)) }

      it 'says it posts, and that posting is permanent' do
        expect(page).to have_button('Post entry', disabled: true)
        expect(page).to have_css('#entry-save-consequence', text: 'Posting records the entry permanently', visible: :all)
        expect(page).to have_css('#entry-save-consequence', text: 'another person must validate', visible: :all)
      end
    end

    it 'ties Save to the consequence as well as to the balance state' do
      expect(page.find('.entry-totals-bar input[type=submit]', visible: :all)['aria-describedby']).to include('entry-balance-status', 'entry-save-consequence')
    end
  end

  describe 'server errors' do
    let(:entry) do
      build(:journal_entry, journal: journals.first, fiscal_year: fiscal_year).tap do |e|
        e.errors.add(:base, 'The period is closed')
        e.errors.add(:entry_date, 'is outside the fiscal year')
      end
    end

    it 'summarises them at the top, as an alert the controller can focus' do
      expect(page).to have_css('[data-entry-errors][role=alert][tabindex="-1"]', text: 'The period is closed')
      expect(page).to have_css('[data-entry-errors]', text: 'Entry date is outside the fiscal year')
    end
  end

  describe 'account field errors' do
    it 'has an inline message for a typed account that matches nothing' do
      expect(page).to have_css('.entry-lines [data-account-search-target=error]', text: 'Choose an account from the list', visible: :all)
    end
  end

  describe 'a saved line' do
    let(:entry) do
      build(:journal_entry, journal: journals.first, fiscal_year: fiscal_year).tap do |e|
        e.lines.build(account: accounts.first, debit: BigDecimal('10'))
      end
    end

    it 'shows the account name next to its code, not the code alone' do
      expect(page).to have_css('input[data-account-search-target=input][value="604000 — Services divers"]')
    end
  end

  describe 'a line already in a foreign currency' do
    let(:entry) do
      build(:journal_entry, journal: journals.first, fiscal_year: fiscal_year).tap do |e|
        e.lines.build(currency: 'USD', amount_currency: BigDecimal('100'), exchange_rate: BigDecimal('1.25'), debit: BigDecimal('80'))
      end
    end

    it 'opens its details so the rate is not hidden' do
      expect(page).to have_css('.entry-lines details.line-extras[open]', visible: :all)
    end
  end

  it 'affiche le bouton Ajouter une ligne' do
    expect(page).to have_button('Add a line')
  end

  it 'affiche le bouton Valider' do
    expect(page).to have_button('Save as draft', disabled: true)
  end

  it 'inclut un template pour les nouvelles lignes' do
    expect(page).to have_css('template', visible: :all)
  end

  context 'with analytical axes' do
    let(:axis)         { create(:analytical_axis, :proj) }
    let(:anal_account) { create(:analytical_account, analytical_axis: axis,
                                code: 'PROJ-001', label_fr: 'Project Alpha') }

    before do
      anal_account
      render_inline(described_class.new(
        entry: entry, journals: journals, accounts: accounts, axes: [ axis ]
      ))
    end

    it 'renders an axis section per line' do
      expect(page).to have_css('.analytical-axes-row', visible: :all)
    end

    it 'renders a select for each axis' do
      expect(page).to have_css('select[data-axis-id]', visible: :all)
    end

    it 'renders analytical accounts as options' do
      expect(page).to have_css('option', text: 'Project Alpha', visible: :all)
    end

    it 'includes the axes JSON on the form element' do
      expect(page).to have_css('[data-journal-entry-form-axes-value]')
    end
  end
end

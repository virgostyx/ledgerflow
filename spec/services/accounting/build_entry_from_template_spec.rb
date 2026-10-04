require "rails_helper"

# F07 §10, entry templates: the draft entry built from a template (fixed, percentage and asked amounts, variables in the labels), always
# balanced, never posted; the examples that come with the app.
RSpec.describe Accounting::BuildEntryFromTemplate do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)    { create(:user, role: :accountant) }
  let!(:misc)   { create(:journal, journal_type: :misc) }
  let(:date)    { fiscal_year.start_date + 40 } # a February day

  def template(*lines, name: "Rent", description: "Rent {mois} {année}")
    Accounting::EntryTemplate.new(name: name, journal: misc, description: description).tap do |t|
      lines.each_with_index { |attrs, i| t.lines.build(position: i, **attrs) }
      t.save!
    end
  end

  let(:rent) do
    template({ account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "Rent {mois}" },
             { account: account_440, side: :credit, amount_kind: :percent, percentage: 100, label: "Landlord {période}" })
  end

  describe "the draft" do
    it "builds a balanced draft in the journal of the template, at the date given" do
      result = described_class.call(template: rent, date: date, base_amount: BigDecimal("950"), user: user)

      expect(result).to be_success
      entry = result[:entry]
      expect(entry).to be_draft
      expect(entry).to have_attributes(journal_id: misc.id, entry_date: date, fiscal_year_id: fiscal_year.id, created_by_id: user.id)
      expect(entry.lines.map { |l| [ l.account_id, l.debit, l.credit ] }).to match_array([ [ account_604.id, 950, 0 ], [ account_440.id, 0, 950 ] ])
    end

    it "fills the variables of the description and of the labels" do
      entry = described_class.call(template: rent, date: date, base_amount: 950)[:entry]

      month = I18n.l(date, format: "%B")
      expect(entry.description).to eq("Rent #{month} #{date.year}")
      expect(entry.lines.pluck(:label)).to match_array([ "Rent #{month}", "Landlord #{month} #{date.year}" ])
    end

    it "takes fixed amounts as they are, and amounts asked for the line" do
      t = template({ account: account_604, side: :debit, amount_kind: :input, label: "Expense" },
                   { account: account_440, side: :credit, amount_kind: :fixed, amount: 200, label: "Supplier" })
      input_line = t.lines.find_by(account: account_604)

      result = described_class.call(template: t, date: date, inputs: { input_line.id => "200" })

      expect(result).to be_success
      expect(result[:entry].lines.find_by(account: account_604).debit).to eq(200)
    end

    it "rounds a percentage to the cent" do
      t = template({ account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "x" },
                   { account: account_440, side: :credit, amount_kind: :percent, percentage: 100, label: "y" })

      expect(described_class.call(template: t, date: date, base_amount: BigDecimal("10.005"))[:entry].lines.first.debit).to eq(BigDecimal("10.01"))
    end

    it "is never posted" do
      expect(described_class.call(template: rent, date: date, base_amount: 10)[:entry]).to be_draft
    end
  end

  describe "refusals" do
    it "asks for the base amount when a line is a percentage of it" do
      expect(described_class.call(template: rent, date: date)).to be_failure
    end

    it "asks for every amount that is to be typed" do
      t = template({ account: account_604, side: :debit, amount_kind: :input, label: "a" }, { account: account_440, side: :credit, amount_kind: :fixed, amount: 5, label: "b" })

      expect(described_class.call(template: t, date: date).message).to include("amount")
    end

    it "refuses an entry that would not balance, creating nothing" do
      t = template({ account: account_604, side: :debit, amount_kind: :percent, percentage: 100, label: "a" },
                   { account: account_440, side: :credit, amount_kind: :percent, percentage: 90, label: "b" })

      expect { expect(described_class.call(template: t, date: date, base_amount: 100)).to be_failure }.not_to change(Accounting::JournalEntry, :count)
    end

    it "refuses a date outside every fiscal year" do
      expect(described_class.call(template: rent, date: fiscal_year.end_date + 400, base_amount: 10)).to be_failure
    end

    it "refuses when an account of the template is archived, naming it" do
      account_604.update!(active: false)

      result = described_class.call(template: rent, date: date, base_amount: 10)

      expect(result).to be_failure
      expect(result.message).to include("604000")
    end
  end

  describe "the template itself" do
    it "needs a name, a journal and at least two lines" do
      expect(Accounting::EntryTemplate.new(name: "", journal: misc)).not_to be_valid
      lone = Accounting::EntryTemplate.new(name: "x", journal: misc)
      lone.lines.build(account: account_604, side: :debit, amount_kind: :fixed, amount: 1, position: 0, label: "a")
      expect(lone).not_to be_valid
    end

    it "needs the amount that its kind calls for" do
      line = Accounting::EntryTemplateLine.new(account: account_604, side: :debit, amount_kind: :fixed, position: 0, label: "a")
      expect(line).not_to be_valid
      line.amount_kind = :percent
      expect(line).not_to be_valid
    end

    it "keeps a name once per entity" do
      rent
      expect(Accounting::EntryTemplate.new(name: "Rent", journal: misc)).not_to be_valid
    end
  end
end

RSpec.describe Accounting::SeedEntryTemplates do
  include_context "with_open_fiscal_year"

  let!(:misc) { create(:journal, journal_type: :misc) }

  it "adds the examples whose accounts exist, and only once" do
    %w[610100 440000 610400 490100 630200 249000 651100 550100 450100 410100].each { |code| create(:account, code: code, label_fr: code, account_class: code[0].to_i, entity: entity) }

    expect(described_class.call).to eq(5)
    expect(described_class.call).to eq(0)
    expect(Accounting::EntryTemplate.pluck(:name)).to include("Rent", "Annual insurance with a deferred charge", "Depreciation", "Bank charges", "VAT regularisation")
  end

  it "skips the example of a missing account, without failing" do
    create(:account, code: "610100", label_fr: "Rent", account_class: 6, entity: entity)
    create(:account, code: "440000", label_fr: "Suppliers", account_class: 4, entity: entity)

    expect(described_class.call).to eq(1)
  end
end

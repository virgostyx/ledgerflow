require "rails_helper"

# F01: an access may be limited to some journals (user_entities.journal_ids; none = all journals).
# Entries and invoices of the other journals are neither listed nor opened, changed, validated or reversed.
RSpec.describe "Journal restriction of an access" do
  include_context "with_open_fiscal_year"

  let!(:sales)    { create(:journal, :sale) }
  let!(:purchase) { create(:journal, :purchase) }
  let(:user)      { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }

  let!(:sales_entry)    { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, journal: sales) }
  let!(:purchase_entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, journal: purchase) }

  def policy(record) = Accounting::JournalEntryPolicy.new(user, record)
  def visible = Accounting::JournalEntryPolicy::Scope.new(user, Accounting::JournalEntry).resolve

  context "without a restriction (the default)" do
    it "reaches every journal" do
      expect([ sales_entry, purchase_entry ]).to all(satisfy { |entry| policy(entry).show? && policy(entry).post? })
      expect(visible).to contain_exactly(sales_entry, purchase_entry)
    end
  end

  context "limited to the sales journal" do
    before { membership.update!(journal_ids: [ sales.id ]) }

    it "allows what the role allows in that journal" do
      expect(policy(sales_entry)).to have_attributes(show?: true, update?: true, post?: true, reverse?: true)
    end

    it "denies everything on the other journals, whatever the role" do
      expect(policy(purchase_entry)).to have_attributes(show?: false, update?: false, edit?: false, post?: false, reverse?: false)
    end

    it "denies creating an entry in another journal, and allows the empty form" do
      expect(policy(build(:journal_entry, journal: purchase)).create?).to be false
      expect(policy(build(:journal_entry, journal: sales)).create?).to be true
      expect(policy(Accounting::JournalEntry.new).new?).to be true
    end

    it "lists only the entries of its journals" do
      expect(visible).to contain_exactly(sales_entry)
    end

    it "does not restrict what the role itself forbids" do
      membership.update!(role: :manager, journal_ids: [ sales.id ])

      expect(policy(sales_entry).post?).to be false
    end

    it "applies to invoices through their journal" do
      other_sales = create(:journal, :sale, code: "VT2", label_fr: "Second sales journal")
      mine   = create(:invoice, :draft, fiscal_year: fiscal_year, journal: sales)
      theirs = create(:invoice, :draft, fiscal_year: fiscal_year, journal: other_sales)

      expect(Accounting::InvoicePolicy.new(user, mine)).to have_attributes(show?: true, post?: true)
      expect(Accounting::InvoicePolicy.new(user, theirs)).to have_attributes(show?: false, post?: false, update?: false)
      expect(Accounting::InvoicePolicy::Scope.new(user, Accounting::Invoice).resolve).to contain_exactly(mine)
    end
  end

  describe "the access itself" do
    it "treats an empty selection as no restriction" do
      membership.update!(journal_ids: [])

      expect(membership.reload.journal_ids).to be_nil
      expect(membership.allows_journal?(purchase.id)).to be true
    end

    it "keeps only whole numbers" do
      membership.update!(journal_ids: [ sales.id.to_s, "", "x", nil ])

      expect(membership.reload.journal_ids).to eq([ sales.id ])
    end

    it "refuses a journal of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:journal, :sale) }

      expect(membership.update(journal_ids: [ foreign.id ])).to be false
      expect(membership.errors[:journal_ids]).to be_present
    end

    it "is per entity: the same person keeps every journal in another entity" do
      membership.update!(journal_ids: [ sales.id ])
      other = create(:entity)
      create(:user_entity, :accountant, user: user, entity: other)
      foreign_journal = ActsAsTenant.with_tenant(other) { create(:journal, :sale) }
      foreign_entry   = ActsAsTenant.with_tenant(other) { create(:journal_entry, :with_balanced_lines, journal: foreign_journal, fiscal_year: create(:fiscal_year)) }

      ActsAsTenant.with_tenant(other) { expect(policy(foreign_entry).show?).to be true }
    end
  end
end

RSpec.describe "Journal restriction on screens", type: :request do
  include_context "with_open_fiscal_year"

  let!(:sales)    { create(:journal, :sale) }
  let!(:purchase) { create(:journal, :purchase) }
  let(:assistant) { create(:user, role: :auditor) }
  let!(:membership) { create(:user_entity, :assistant, user: assistant, entity: entity, journal_ids: [ sales.id ]) }
  let!(:sales_entry)    { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, journal: sales, description: "SALES-VISIBLE") }
  let!(:purchase_entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, journal: purchase, description: "PURCHASE-HIDDEN") }

  before { sign_in assistant }

  it "lists only the entries of the allowed journals" do
    get accounting_journal_entries_path

    expect(response.body).to include("SALES-VISIBLE")
    expect(response.body).not_to include("PURCHASE-HIDDEN")
  end

  it "refuses to open an entry of another journal" do
    get accounting_journal_entry_path(purchase_entry)

    expect(response.body).not_to include("PURCHASE-HIDDEN")
    expect(response).to redirect_to(accounting_root_path)
  end

  it "refuses to write an entry in another journal" do
    params = { accounting_journal_entry: { journal_id: purchase.id, fiscal_year_id: fiscal_year.id, entry_date: Date.current, description: "sneaky",
                                           lines_attributes: { "0" => { account_id: create(:account).id, debit: "10", credit: "0", label: "a" },
                                                               "1" => { account_id: create(:account).id, debit: "0", credit: "10", label: "b" } } } }

    expect { post accounting_journal_entries_path, params: params }.not_to change(Accounting::JournalEntry, :count)
  end
end

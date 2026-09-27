require "rails_helper"

RSpec.describe Accounting::PostedLine, type: :model do
  include_context "with_open_fiscal_year"

  let(:account) { create(:account, entity: entity) }

  it "includes lines from a posted entry, denormalizing the entry's date and journal" do
    entry = create(:journal_entry, :posted, :with_balanced_lines, entity: entity, fiscal_year: fiscal_year)
    line  = entry.lines.first

    posted_line = described_class.find(line.id)

    expect(posted_line.entity_id).to eq(entity.id)
    expect(posted_line.fiscal_year_id).to eq(fiscal_year.id)
    expect(posted_line.journal_id).to eq(entry.journal_id)
    expect(posted_line.entry_date).to eq(entry.entry_date)
    expect(posted_line.account_id).to eq(line.account_id)
    expect(posted_line.debit).to eq(line.debit)
    expect(posted_line.credit).to eq(line.credit)
  end

  it "excludes lines from a draft entry" do
    entry = create(:journal_entry, :draft, :with_unbalanced_lines, entity: entity, fiscal_year: fiscal_year)
    line  = entry.lines.first

    expect(described_class.where(id: line.id)).to be_empty
  end

  it "excludes lines from a reversed entry" do
    entry = create(:journal_entry, :posted, :with_balanced_lines, entity: entity, fiscal_year: fiscal_year)
    line  = entry.lines.first
    entry.update_column(:status, Accounting::JournalEntry.statuses[:reversed])

    expect(described_class.where(id: line.id)).to be_empty
  end

  it "scopes to the current tenant" do
    other_entity = create(:entity)
    entry = create(:journal_entry, :posted, :with_balanced_lines, entity: entity, fiscal_year: fiscal_year)
    line  = entry.lines.first

    ActsAsTenant.with_tenant(other_entity) do
      expect(described_class.where(id: line.id)).to be_empty
    end
  end

  it "is read-only" do
    entry = create(:journal_entry, :posted, :with_balanced_lines, entity: entity, fiscal_year: fiscal_year)
    posted_line = described_class.find(entry.lines.first.id)

    expect { posted_line.update!(label: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end

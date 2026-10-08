require "rails_helper"

RSpec.describe Accounting::CreateDraftEntry do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user) }
  let(:journal) { create(:journal, :purchase) }
  let(:attributes) do
    { journal_id: journal.id, fiscal_year_id: fiscal_year.id, entry_date: fiscal_year.start_date + 5, description: "Rent",
      lines_attributes: { "0" => { account_id: account_604.id, debit: "100.00", credit: "0" }, "1" => { account_id: account_440.id, debit: "0", credit: "100.00" } } }
  end

  it "saves a balanced entry as a draft, with its lines and its author" do
    result = described_class.call(attributes: attributes, user: user)

    expect(result).to be_saved
    expect(result.entry).to have_attributes(status: "draft", created_by_id: user.id, source_type: nil)
    expect(result.entry.lines.count).to eq(2)
  end

  it "says where a generated draft comes from" do
    result = described_class.call(attributes: attributes, user: user, source: [ "Agent::Proposal", 7 ])

    expect(result.entry).to have_attributes(source_type: "Agent::Proposal", source_id: 7)
  end

  it "does not check the balance: a draft may be unbalanced, the posting refuses it (the agent's proposals are balanced before they get here)" do
    attributes[:lines_attributes]["1"][:credit] = "90.00"

    expect(described_class.call(attributes: attributes, user: user).entry.status).to eq("draft")
  end

  it "does not save an entry that the model refuses, and leaves nothing behind" do
    expect { @result = described_class.call(attributes: attributes.merge(entry_date: nil), user: user) }.not_to change(Accounting::JournalEntry, :count)
    expect(@result).not_to be_saved
  end
end

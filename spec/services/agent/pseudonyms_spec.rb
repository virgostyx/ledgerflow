require "rails_helper"

RSpec.describe Agent::Pseudonyms do
  include_context "with entity"

  let(:conversation) { Agent::Conversation.create!(user: create(:user), title: "t") }
  let(:table) { described_class.new(conversation) }

  it "gives the same token to the same value, and a new number to a new one" do
    first = table.token_for("Alice Dupont", "person")

    expect(first).to eq("PERSONNE_001")
    expect(table.token_for("Alice Dupont", "person")).to eq(first)
    expect(table.token_for("Bob Martin", "person")).to eq("PERSONNE_002")
    expect(table.token_for("BE0123456789", "tax_identifier")).to eq("TVA_001")
  end

  it "keeps the table for the conversation: a new instance finds the same tokens" do
    table.token_for("Alice Dupont", "person")

    expect(described_class.new(conversation).token_for("Alice Dupont", "person")).to eq("PERSONNE_001")
    expect(described_class.new(conversation).token_for("Carol", "person")).to eq("PERSONNE_002")
  end

  it "does not share a table between conversations" do
    other = Agent::Conversation.create!(user: create(:user), title: "o")

    table.token_for("Alice Dupont", "person")

    expect(described_class.new(other).token_for("Zoé Leroy", "person")).to eq("PERSONNE_001")
    expect(described_class.new(other).reveal("PERSONNE_001")).to eq("Zoé Leroy")
  end

  it "keeps the real values encrypted in the database" do
    table.token_for("Alice Dupont", "person")

    raw = ActiveRecord::Base.connection.select_value("SELECT real_value FROM agent_pseudonyms LIMIT 1")
    expect(raw).not_to include("Alice")
  end

  it "turns the tokens of a text back into what they stand for, and leaves one that is not in the table" do
    table.token_for("Alice Dupont", "person")
    table.token_for("BE0123456789", "tax_identifier")

    text = "PERSONNE_001 owes 10.00 (TVA_001); PERSONNE_099 is not known."

    expect(table.reveal(text)).to eq("Alice Dupont owes 10.00 (BE0123456789); PERSONNE_099 is not known.")
    expect(table.unknown_tokens(text)).to eq([ "PERSONNE_099" ])
  end

  it "does not touch a text with no token" do
    expect(table.reveal("nothing here")).to eq("nothing here")
    expect(table.reveal(nil)).to be_nil
  end

  it "finds a token that another view of the same table created first" do
    other_view = described_class.new(conversation)
    table.token_for("Alice Dupont", "person") # the first view creates PERSONNE_001
    allow(conversation.pseudonyms).to receive(:create!).and_call_original

    expect(other_view.token_for("Alice Dupont", "person")).to eq("PERSONNE_001")
  end
end

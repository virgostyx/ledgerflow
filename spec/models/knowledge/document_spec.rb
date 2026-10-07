require "rails_helper"

RSpec.describe Knowledge::Document do
  include_context "with entity"

  let(:other_entity) { create(:entity) }
  let(:organization) { Organization.create!(name: "Firm") }

  it "shows an entity the platform's documents, its organization's and its own, and nothing of another entity" do
    entity.update!(organization: organization)
    platform = add_knowledge("# P\n\nPlatform note about leases.", scope: "platform")
    firm     = add_knowledge("# F\n\nFirm note about leases.", scope: "organization", organization: organization)
    mine     = add_knowledge("# M\n\nOur note about leases.")
    theirs   = add_knowledge("# T\n\nTheir note about leases.", entity: other_entity)
    elsewhere = add_knowledge("# O\n\nAnother firm note about leases.", scope: "organization", organization: Organization.create!(name: "Other"), entity: other_entity)

    visible = described_class.visible_to(entity)

    expect(visible).to contain_exactly(platform, firm, mine)
    expect(visible).not_to include(theirs, elsewhere)
  end

  it "uses a document only when it is reviewed and in force on the day" do
    ended   = add_knowledge("# A\n\nEnded rule.", valid_from: Date.new(2020, 1, 1), valid_to: Date.new(2022, 12, 31))
    current = add_knowledge("# B\n\nCurrent rule.", valid_from: Date.new(2023, 1, 1))
    future  = add_knowledge("# C\n\nFuture rule.", valid_from: Date.new(2030, 1, 1))
    draft   = add_knowledge("# D\n\nDraft rule.", reviewed: false)
    retired = add_knowledge("# E\n\nRetired rule.").tap(&:retire!)

    expect(described_class.usable_by(entity, on: Date.new(2026, 6, 1))).to contain_exactly(current)
    expect(described_class.usable_by(entity, on: Date.new(2022, 6, 1))).to contain_exactly(ended)
    expect(described_class.usable_by(entity, on: Date.new(2031, 1, 1))).to include(future)
    expect([ draft, retired ]).to all(satisfy { |document| !described_class.usable_by(entity, on: Date.new(2026, 6, 1)).include?(document) })
  end

  describe "#review!" do
    let(:author) { create(:user) }
    let(:document) { add_knowledge("# A\n\nA rule of ours.", reviewed: false, author: author) }

    it "lets another person review it" do
      reviewer = create(:user)
      document.review!(reviewer, four_eyes: true)

      expect(document).to have_attributes(status: "reviewed", reviewed_by_id: reviewer.id)
      expect(document.reviewed_at).to be_present
    end

    it "refuses the author when four-eyes is on, and allows them when it is off" do
      expect { document.review!(author, four_eyes: true) }.to raise_error(ArgumentError, /four-eyes/)
      document.review!(author, four_eyes: false)

      expect(document).to be_reviewed
    end

    it "reviews a draft only" do
      expect { add_knowledge("# R\n\nAlready reviewed rule.").review!(create(:user), four_eyes: false) }.to raise_error(ArgumentError, /draft/)
    end
  end

  it "knows what an entity can change: its own documents, never the platform's" do
    expect(add_knowledge("# M\n\nOurs.").editable_by?(entity)).to be true
    expect(add_knowledge("# P\n\nPlatform.", scope: "platform").editable_by?(entity)).to be false
  end

  it "has a reference that opens it" do
    document = add_knowledge("# M\n\nOurs.")

    expect(document.ref).to eq("kb:doc-#{document.id}")
    expect(Agent::Refs.path(document.chunks.first.ref)).to eq("/agent/knowledge_documents/#{document.id}#p-1")
  end

  it "gives a passage's excerpt at most 1200 characters, from the stretch that holds the words searched" do
    filler = "Nothing relevant is said in this sentence. " * 40
    chunk = add_knowledge("# Long\n\n#{filler}The prepayment of insurance is spread over the year. #{filler}").chunks.first

    excerpt = chunk.excerpt([ "prepayment" ])

    expect(excerpt.length).to be <= Knowledge::Chunk::EXCERPT_LENGTH + 2
    expect(excerpt).to include("prepayment")
  end
end

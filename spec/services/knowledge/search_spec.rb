require "rails_helper"

RSpec.describe Knowledge::Search do
  include_context "with entity"

  let(:corpus) { YAML.safe_load_file(Rails.root.join("spec/fixtures/knowledge/labeled_corpus.yml")) }
  let(:other_entity) { create(:entity) }

  def search(query, **options) = described_class.call(entity: entity, query: query, **options)

  it "finds the right passage among the first five for at least 90% of the labeled questions" do
    documents = corpus["documents"].transform_values { |doc| add_knowledge(doc["text"], title: doc["title"], language: doc["language"]) }

    found = corpus["questions"].count do |question|
      hits = search(question["q"], top_k: 5)
      hits.any? { |hit| hit.document.id == documents.fetch(question["doc"]).id && hit.chunk.section == question["section"] }
    end

    expect(found.to_f / corpus["questions"].size).to be >= 0.9
  end

  it "ignores accents in the question and in the text" do
    add_knowledge("# Loyers\n\nUne charge constatée d'avance est un loyer payé d'avance.", language: "fr")

    expect(search("charges constatees")).not_to be_empty
  end

  it "never returns a passage of another entity, not even one that matches better" do
    add_knowledge("# Secret\n\nOur secret treatment of prepayment of insurance premiums.", entity: other_entity)
    mine = add_knowledge("# Mine\n\nPrepayment of insurance premiums.")

    expect(search("prepayment insurance premiums").map(&:document)).to eq([ mine ])
  end

  it "uses only the documents in force on the day of the operation, not the day of the question" do
    old = add_knowledge("# Rule\n\nThe old rule on depreciation of computers: five years.", valid_from: Date.new(2018, 1, 1), valid_to: Date.new(2022, 12, 31))
    new = add_knowledge("# Rule\n\nThe new rule on depreciation of computers: three years.", valid_from: Date.new(2023, 1, 1))

    expect(search("depreciation computers", as_of: Date.new(2021, 5, 1)).map(&:document)).to eq([ old ])
    expect(search("depreciation computers", as_of: Date.new(2025, 5, 1)).map(&:document)).to eq([ new ])
  end

  it "does not use a draft or a withdrawn document" do
    add_knowledge("# Rule\n\nDraft rule on depreciation of computers.", reviewed: false)
    add_knowledge("# Rule\n\nWithdrawn rule on depreciation of computers.").retire!

    expect(search("depreciation computers")).to be_empty
  end

  it "puts a passage of low quality after the others" do
    add_knowledge("# Table\n\n| depreciation | 3 | 5 | 7 | 9 | 11 |\n| computers | 3 | 5 | 7 | 9 | 11 |")
    good = add_knowledge("# Text\n\nComputers are depreciated over three years, which is the depreciation rule of the firm.")

    hits = search("depreciation computers")

    expect(hits.first.document).to eq(good)
    expect(hits.last.chunk.quality).to eq("low")
  end

  it "filters by country and by kind of source" do
    add_knowledge("# R\n\nDepreciation of computers in Belgium.", jurisdiction: "BE", source_type: "sheet")
    add_knowledge("# R\n\nDepreciation of computers in France.", jurisdiction: "FR", source_type: "note")

    expect(search("depreciation computers", jurisdiction: "FR").map { |hit| hit.document.jurisdiction }).to eq([ "FR" ])
    expect(search("depreciation computers", source_types: [ "sheet" ]).map { |hit| hit.document.source_type }).to eq([ "sheet" ])
  end

  it "cannot be steered by the syntax of the search: only the words count" do
    add_knowledge("# R\n\nDepreciation of computers over three years.")

    expect { search("computers' | !(& :* <-> ) ; DROP TABLE") }.not_to raise_error
    expect(search("&&& || !!")).to eq([])
  end

  it "gives at most top_k passages" do
    8.times { |i| add_knowledge("# R#{i}\n\nDepreciation of computers, note #{i}.") }

    expect(search("depreciation computers", top_k: 3).size).to eq(3)
  end
end

require "rails_helper"

RSpec.describe Knowledge::Chunker do
  def paragraph(word, size) = ([ word ] * size).join(" ") + "."

  it "attaches each passage to the title of its section, in Markdown or numbered" do
    passages = described_class.call("# Prepayments\n\nBook the part of the invoice that belongs to next year on a prepayment account.\n\n2.1 Accruals\n\nBook the expense not yet invoiced on an accrual account at year end.")

    expect(passages.map(&:section)).to eq([ "Prepayments", "2.1 Accruals" ])
    expect(passages.first.content).to include("prepayment account")
  end

  it "cuts a long section into passages of about 600 tokens that overlap, so that a rule cut in two is found from either side" do
    text = "# Long\n\n" + (1..30).map { |i| paragraph("rule#{i}", 60) }.join("\n\n")

    passages = described_class.call(text)

    expect(passages.size).to be > 1
    expect(passages.map { |p| p.content.length }.max).to be <= described_class::HARD_MAX
    expect(passages.each_cons(2).all? { |a, b| (a.content.split.last(10) & b.content.split.first(60)).any? }).to be true
  end

  it "cuts a paragraph that is longer than a passage" do
    passages = described_class.call(paragraph("word", 2000))

    expect(passages.size).to be > 1
    expect(passages.map { |p| p.content.length }.max).to be <= described_class::HARD_MAX
  end

  it "marks a table or a footnote as low quality, and prose as normal" do
    passages = described_class.call("# T\n\n| 12 | 34 | 56 |\n| 78 | 90 | 11 |\n\n# P\n\nA prepayment is an expense paid in advance, booked on an asset account until the period it belongs to.\n\n# F\n\n(1) see above")

    expect(passages.map(&:quality)).to eq(%w[low normal low])
  end

  it "gives nothing for an empty text" do
    expect(described_class.call("  \n\n ")).to eq([])
  end
end

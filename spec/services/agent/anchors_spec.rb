require "rails_helper"

RSpec.describe Agent::Anchors do
  subject(:anchors) { described_class.new(question: "Is 50.00 right?", earlier_answers: [ "Customers owe 4598.00 EUR." ]) }

  it "knows the amounts of the question and of the earlier answers" do
    expect(anchors.unanchored("Yes, 50.00. Last time 4 598,00.")).to be_empty
  end

  it "learns the amounts of every tool result" do
    anchors.add_result({ "data" => [ { "total" => "1210.00" } ], "totals" => { "total" => "2420.00" } }.to_json)

    expect(anchors.unanchored("1 210,00 and 2420.00")).to be_empty
  end

  it "names the amounts of a text that nobody gave" do
    expect(anchors.unanchored("It is 9999.99, and 50.00")).to eq([ "9999.99" ])
  end

  it "checks the amounts handed to a calculation, but not its constants" do
    anchors.add_result({ "total" => "3800.00" }.to_json)

    expect(anchors.unanchored_inputs([ "3800.00", "12", "0.5", "-3800.00", "1.2345" ])).to be_empty
    expect(anchors.unanchored_inputs([ "3800.00", "123.45", "-99.00" ])).to eq([ "123.45", "99.00" ])
  end

  it "lets the second factor of a multiplication be a rate, and only that" do
    anchors.add_result({ "total" => "3800.00" }.to_json)
    expect(anchors.unanchored_inputs([ "3800.00", "0.21" ], operation: "multiply")).to be_empty
    expect(anchors.unanchored_inputs([ "0.21", "3800.00" ], operation: "multiply")).to eq([ "0.21" ])
    expect(anchors.unanchored_inputs([ "3800.00", "0.21" ], operation: "sum")).to eq([ "0.21" ])
  end
end

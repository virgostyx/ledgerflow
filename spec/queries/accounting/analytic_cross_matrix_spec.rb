require "rails_helper"

RSpec.describe Accounting::AnalyticCrossQuery, ".matrix" do
  def account(id, code) = Struct.new(:id, :code).new(id, code)

  let(:a1) { account(1, "A-1") }
  let(:a2) { account(2, "A-2") }
  let(:b1) { account(10, "B-1") }
  let(:b2) { account(11, "B-2") }

  def cell(row, col) = Accounting::AnalyticCrossQuery::Result.new(row_account: row, col_account: col, charges: 0, produits: 0, solde: 0)

  it "lists distinct row and column accounts sorted by code, and indexes the cells by [row id, column id]" do
    results = [ cell(a2, b2), cell(a1, b2), cell(a2, b1) ]

    matrix = described_class.matrix(results)

    expect(matrix.row_accounts).to eq([ a1, a2 ])
    expect(matrix.col_accounts).to eq([ b1, b2 ])
    expect(matrix.cells.keys).to contain_exactly([ 2, 11 ], [ 1, 11 ], [ 2, 10 ])
    expect(matrix.cells[[ 1, 11 ]]).to be(results[1])
  end

  it "is empty without results" do
    matrix = described_class.matrix([])

    expect([ matrix.row_accounts, matrix.col_accounts, matrix.cells ]).to eq([ [], [], {} ])
  end
end

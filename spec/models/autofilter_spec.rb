require 'rails_helper'

# Exercised through Accounting::Invoice, which declares one column of each type.
RSpec.describe 'ApplicationRecord.autofilter', type: :model do
  include_context 'with_open_fiscal_year'

  let(:model) { Accounting::Invoice }
  let!(:acme)   { create(:partner, name: 'Acme') }
  let!(:globex) { create(:partner, name: 'Globex') }
  let!(:a) { create(:invoice, fiscal_year: fiscal_year, partner: acme,   invoice_date: Date.new(2025, 1, 5),  total_incl_vat: 100) }
  let!(:b) { create(:invoice, :posted, fiscal_year: fiscal_year, partner: globex, invoice_date: Date.new(2025, 3, 5), total_incl_vat: 300) }
  let!(:c) { create(:invoice, :paid, invoice_number: 'VTE-PAID', fiscal_year: fiscal_year, partner: globex, invoice_date: Date.new(2025, 5, 5), total_incl_vat: 200) }

  def run(**opts) = model.autofilter(**opts)

  it 'returns everything without arguments' do
    expect(run).to contain_exactly(a, b, c)
  end

  it 'filters a string column on several values' do
    expect(run(f: { 'partner' => %w[Acme] })).to contain_exactly(a)
    expect(run(f: { 'partner' => %w[Acme Globex] })).to contain_exactly(a, b, c)
  end

  it 'filters an enum column with keys' do
    expect(run(f: { 'status' => %w[posted paid] })).to contain_exactly(b, c)
  end

  it 'ignores unknown enum keys' do
    expect(run(f: { 'status' => %w[bogus] })).to be_empty
  end

  it 'filters a date column by range' do
    expect(run(f: { 'invoice_date' => { 'from' => '2025-02-01', 'to' => '2025-04-01' } })).to contain_exactly(b)
    expect(run(f: { 'invoice_date' => { 'from' => '2025-02-01' } })).to contain_exactly(b, c)
  end

  it 'ignores an unparsable date' do
    expect(run(f: { 'invoice_date' => { 'from' => 'nope' } })).to contain_exactly(a, b, c)
  end

  it 'filters a decimal column by range' do
    expect(run(f: { 'total_incl_vat' => { 'min' => '150', 'max' => '250' } })).to contain_exactly(c)
  end

  it 'ignores an unparsable number' do
    expect(run(f: { 'total_incl_vat' => { 'min' => 'x' } })).to contain_exactly(a, b, c)
  end

  it 'combines several columns' do
    expect(run(f: { 'partner' => %w[Globex], 'status' => %w[paid] })).to contain_exactly(c)
  end

  it 'ignores undeclared columns (no SQL injection surface)' do
    expect(run(f: { 'id; DROP TABLE x' => %w[1], 'entity_id' => %w[0] })).to contain_exactly(a, b, c)
  end

  it 'skips the excepted column' do
    expect(run(f: { 'partner' => %w[Acme] }, except: 'partner')).to contain_exactly(a, b, c)
  end

  describe 'boolean column' do
    let(:model) { Accounting::Account }
    let!(:live) { create(:account, active: true) }
    let!(:dead) { create(:account, active: false) }

    it 'filters on true/false keys' do
      expect(run(f: { 'active' => %w[true] })).to contain_exactly(live)
      expect(run(f: { 'active' => %w[false] })).to contain_exactly(dead)
      expect(run(f: { 'active' => %w[true false] })).to contain_exactly(live, dead)
    end

    it 'matches nothing for unknown keys' do
      expect(run(f: { 'active' => %w[maybe] })).to be_empty
    end
  end

  describe 'sorting' do
    it 'sorts asc and desc on a declared column, through a join' do
      expect(run(sort: 'partner', dir: 'asc').first).to eq(a)
      expect(run(sort: 'total_incl_vat', dir: 'desc').map(&:id)).to eq([ b, c, a ].map(&:id))
    end

    it 'falls back to the existing order for an undeclared column or bad direction' do
      expect(run(sort: 'nope', dir: 'asc').to_sql).not_to include('nope')
      expect(run(sort: 'total_incl_vat', dir: 'sideways').to_sql).to match(/ASC\z/)
    end
  end

  describe '.autofilter_values' do
    it 'lists distinct sorted values of a string column, ignoring its own filter' do
      expect(model.autofilter_values('partner', f: { 'partner' => %w[Acme] })).to eq(%w[Acme Globex])
    end

    it 'respects the other filters' do
      expect(model.autofilter_values('partner', f: { 'status' => %w[draft] })).to eq(%w[Acme])
    end

    it 'returns nothing for an undeclared or non-string column' do
      expect(model.autofilter_values('status')).to eq([])
      expect(model.autofilter_values('nope')).to eq([])
    end
  end
end

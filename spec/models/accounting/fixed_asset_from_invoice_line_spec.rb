require 'rails_helper'

RSpec.describe Accounting::FixedAsset, 'created from a purchase invoice line', type: :model do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:asset_account) { create(:account, code: '240200', label_fr: 'Matériel informatique', account_class: 2, account_type: :asset, normal_balance: :debit) }
  let(:supplier) { create(:partner, :supplier) }

  def posted_purchase(account: asset_account, document_type: :invoice, invoice_type: :supplier, unit_price: '1000.00', currency: 'EUR', exchange_rate: 1, vat_rate: '21.00', description: 'Laptops for the team')
    inv = create(:invoice, invoice_type: invoice_type, partner: supplier, fiscal_year: fiscal_year, currency: currency, exchange_rate: exchange_rate,
                 journal: invoice_type == :supplier ? purchase_journal : create(:journal, :sale), document_type: document_type)
    create(:invoice_line, invoice: inv, account: account, quantity: 1, unit_price: unit_price, vat_rate: vat_rate, description: description, position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  def asset_for(line, **attrs)
    build(:fixed_asset, description: 'Laptops', invoice_line: line, asset_account: line.account, **attrs)
  end

  describe '.depreciable_account?' do
    %w[210200 220200 230200 240200].each do |code|
      it "accepte le compte #{code}" do
        expect(described_class.depreciable_account?(build(:account, code: code))).to be true
      end
    end

    %w[220100 250100 604000 400000].each do |code|
      it "refuse le compte #{code}" do
        expect(described_class.depreciable_account?(build(:account, code: code))).to be false
      end
    end
  end

  describe 'the link with an invoice line' do
    let(:line) { posted_purchase.lines.first }

    it 'is valid for a line of an issued supplier invoice, on the line account' do
      expect(asset_for(line)).to be_valid
    end

    it 'stays optional' do
      expect(build(:fixed_asset)).to be_valid
    end

    it 'refuses a line of a draft invoice' do
      draft = create(:invoice, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, journal: purchase_journal)
      draft_line = create(:invoice_line, invoice: draft, account: asset_account, quantity: 1, unit_price: '500.00', vat_rate: '21.00', position: 1)

      expect(asset_for(draft_line)).not_to be_valid
    end

    it 'refuses a line of a customer invoice' do
      customer_line = posted_purchase(invoice_type: :customer, account: create(:account, code: '700100', account_class: 7, account_type: :revenue, normal_balance: :credit)).lines.first
      asset = asset_for(customer_line, asset_account: asset_account)

      expect(asset).not_to be_valid
      expect(asset.errors[:invoice_line]).to be_present
    end

    it 'refuses a line of a credit note' do
      original = posted_purchase
      note = create(:invoice, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, journal: purchase_journal,
                    document_type: :credit_note, credited_invoice: original)
      note_line = create(:invoice_line, invoice: note, account: asset_account, quantity: 1, unit_price: '100.00', vat_rate: '21.00', position: 1)
      Accounting::PostInvoice.call(invoice: note)

      expect(asset_for(note_line)).not_to be_valid
    end

    it 'refuses a line whose account cannot depreciate' do
      expense_line = posted_purchase(account: account_604).lines.first
      asset = build(:fixed_asset, invoice_line: expense_line, asset_account: nil)

      expect(asset).not_to be_valid
      expect(asset.errors[:invoice_line]).to be_present
    end

    it 'requires the asset account to be the account of the line' do
      other = create(:account, code: '230200', account_class: 2, account_type: :asset, normal_balance: :debit)
      asset = asset_for(line, asset_account: other)

      expect(asset).not_to be_valid
      expect(asset.errors[:asset_account]).to be_present
    end

    it 'allows a single asset per line' do
      asset_for(line).save!
      second = asset_for(line)

      expect(second).not_to be_valid
      expect(second.errors[:invoice_line_id]).to be_present
    end

    it 'is also enforced by the database' do
      asset_for(line).save!
      expect { asset_for(line).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.build_from_invoice_line' do
    it 'prefills an unsaved asset from the line' do
      line = posted_purchase(description: 'Laptops for the team').lines.first
      asset = described_class.build_from_invoice_line(line)

      expect(asset).to be_new_record
      expect(asset).to have_attributes(description: 'Laptops for the team', acquisition_date: line.invoice.invoice_date,
                                       acquisition_value: BigDecimal('1000.00'), asset_account: asset_account, invoice_line: line,
                                       asset_category: 'movable', vat_amount_initial: BigDecimal('210.00'),
                                       prorata_at_acquisition: BigDecimal('100'))
    end

    it 'converts the amounts to EUR at the rate of the invoice' do
      line = posted_purchase(currency: 'USD', exchange_rate: BigDecimal('0.9')).lines.first
      asset = described_class.build_from_invoice_line(line)

      expect(asset.acquisition_value).to eq(BigDecimal('900.00'))
      expect(asset.vat_amount_initial).to eq(BigDecimal('189.00')) # 21 % of 1000 USD * 0.9
    end

    it 'applies the prorata of the entity to the deducted VAT' do
      entity.update!(vat_scheme: :mixed, vat_prorata_rate: '80.00')
      line = posted_purchase.lines.first
      asset = described_class.build_from_invoice_line(line)

      expect(asset.vat_amount_initial).to eq(BigDecimal('168.00')) # 210 * 80 %
      expect(asset.prorata_at_acquisition).to eq(BigDecimal('80'))
    end

    it 'is a 15-year immovable for a construction account' do
      building = create(:account, code: '220200', account_class: 2, account_type: :asset, normal_balance: :debit)
      line = posted_purchase(account: building).lines.first

      expect(described_class.build_from_invoice_line(line).asset_category).to eq('immovable')
    end

    it 'yields an asset that only needs a useful life to be saved as depreciable' do
      line = posted_purchase.lines.first
      asset = described_class.build_from_invoice_line(line)
      asset.useful_life_years = 3

      expect(asset).to be_valid
      expect(asset.tap(&:save!)).to be_depreciable
    end
  end
end

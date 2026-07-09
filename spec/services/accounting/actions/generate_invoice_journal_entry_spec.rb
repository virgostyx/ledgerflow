require 'rails_helper'

RSpec.describe Accounting::Actions::GenerateInvoiceJournalEntry, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:sale_journal)     { create(:journal, :sale) }
  let(:partner)           { create(:partner) }

  def post_invoice_with_lines(type:, journal:, lines_data:)
    inv = create(:invoice, invoice_type: type, partner: partner,
                 fiscal_year: fiscal_year, journal: journal)
    lines_data.each_with_index do |data, i|
      create(:invoice_line, invoice: inv, account: data[:account],
             quantity: 1, unit_price: data[:unit_price].to_s,
             vat_rate: data[:vat_rate].to_s, position: i + 1)
    end
    inv.compute_totals
    inv.save!
    Accounting::PostInvoice.call(invoice: inv)
    inv.reload
  end

  # -----------------------------------------------------------------------
  # FACTURES FOURNISSEUR — ACHATS
  # -----------------------------------------------------------------------

  describe 'facture fournisseur — codes grilles TVA achats' do
    context 'taux 21%' do
      subject(:invoice) do
        post_invoice_with_lines(type: :supplier, journal: purchase_journal,
                                lines_data: [{ account: account_604,
                                               unit_price: '1000.00', vat_rate: '21.00' }])
      end

      it 'la ligne dépense (604) a vat_code 81' do
        expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
        expect(expense_line.vat_code).to eq(81)
      end

      it 'la ligne TVA (411000) a vat_code 59' do
        vat_line = invoice.journal_entry.lines.find { |l| l.account == account_411 }
        expect(vat_line.vat_code).to eq(59)
      end

      it 'la ligne TVA a vat_amount correct' do
        vat_line = invoice.journal_entry.lines.find { |l| l.account == account_411 }
        expect(vat_line.vat_amount).to eq(BigDecimal('210.00'))
      end

      it 'la ligne contrepartie (440000) n a pas de vat_code' do
        payable_line = invoice.journal_entry.lines.find { |l| l.account == account_440 }
        expect(payable_line.vat_code).to be_nil
      end

      it "l écriture est équilibrée" do
        entry = invoice.journal_entry
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end

    context 'taux 6%' do
      subject(:invoice) do
        post_invoice_with_lines(type: :supplier, journal: purchase_journal,
                                lines_data: [{ account: account_604,
                                               unit_price: '500.00', vat_rate: '6.00' }])
      end

      it 'la ligne dépense a vat_code 83' do
        expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
        expect(expense_line.vat_code).to eq(83)
      end

      it "l écriture est équilibrée" do
        entry = invoice.journal_entry
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end

    context 'taux 12%' do
      subject(:invoice) do
        post_invoice_with_lines(type: :supplier, journal: purchase_journal,
                                lines_data: [{ account: account_604,
                                               unit_price: '200.00', vat_rate: '12.00' }])
      end

      it 'la ligne dépense a vat_code 82' do
        expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
        expect(expense_line.vat_code).to eq(82)
      end
    end

    context 'taux 0% (exempté)' do
      subject(:invoice) do
        post_invoice_with_lines(type: :supplier, journal: purchase_journal,
                                lines_data: [{ account: account_604,
                                               unit_price: '300.00', vat_rate: '0.00' }])
      end

      it 'la ligne dépense n a pas de vat_code' do
        expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
        expect(expense_line.vat_code).to be_nil
      end

      it 'aucune ligne TVA (411000) n est créée' do
        vat_lines = invoice.journal_entry.lines.select { |l| l.account == account_411 }
        expect(vat_lines).to be_empty
      end

      it "l écriture est équilibrée" do
        entry = invoice.journal_entry
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end

    context 'multi-taux — 21% et 6%' do
      let!(:account_612) do
        create(:account, code: '612000', label_fr: 'Entretien', account_class: 6, entity: entity)
      end

      subject(:invoice) do
        post_invoice_with_lines(type: :supplier, journal: purchase_journal,
                                lines_data: [
                                  { account: account_604, unit_price: '1000.00', vat_rate: '21.00' },
                                  { account: account_612, unit_price: '500.00',  vat_rate: '6.00' }
                                ])
      end

      it 'crée deux lignes TVA distinctes (une par taux)' do
        vat_lines = invoice.journal_entry.lines.select { |l| l.account == account_411 }
        expect(vat_lines.count).to eq(2)
      end

      it 'toutes les lignes TVA ont vat_code 59' do
        vat_lines = invoice.journal_entry.lines.select { |l| l.account == account_411 }
        expect(vat_lines.map(&:vat_code).uniq).to eq([59])
      end

      it 'les montants TVA correspondent à chaque taux' do
        vat_lines = invoice.journal_entry.lines.select { |l| l.account == account_411 }
        amounts = vat_lines.map(&:debit).sort
        # 1000 * 21% = 210, 500 * 6% = 30
        expect(amounts).to eq([BigDecimal('30.00'), BigDecimal('210.00')])
      end

      it "l écriture est équilibrée" do
        entry = invoice.journal_entry
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end
  end

  # -----------------------------------------------------------------------
  # FACTURES CLIENT — VENTES
  # -----------------------------------------------------------------------

  describe 'facture client — codes grilles TVA ventes' do
    context 'taux 21%' do
      subject(:invoice) do
        post_invoice_with_lines(type: :customer, journal: sale_journal,
                                lines_data: [{ account: account_700,
                                               unit_price: '2000.00', vat_rate: '21.00' }])
      end

      it 'la ligne produit (700) a vat_code 1' do
        revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
        expect(revenue_line.vat_code).to eq(1)
      end

      it 'la ligne TVA (451000) a vat_code 54' do
        vat_line = invoice.journal_entry.lines.find { |l| l.account == account_451 }
        expect(vat_line.vat_code).to eq(54)
      end

      it 'la ligne TVA a vat_amount correct' do
        vat_line = invoice.journal_entry.lines.find { |l| l.account == account_451 }
        expect(vat_line.vat_amount).to eq(BigDecimal('420.00'))
      end

      it "l écriture est équilibrée" do
        entry = invoice.journal_entry
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end

    context 'taux 6%' do
      subject(:invoice) do
        post_invoice_with_lines(type: :customer, journal: sale_journal,
                                lines_data: [{ account: account_700,
                                               unit_price: '1000.00', vat_rate: '6.00' }])
      end

      it 'la ligne produit a vat_code 3' do
        revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
        expect(revenue_line.vat_code).to eq(3)
      end
    end

    context 'taux 12%' do
      subject(:invoice) do
        post_invoice_with_lines(type: :customer, journal: sale_journal,
                                lines_data: [{ account: account_700,
                                               unit_price: '800.00', vat_rate: '12.00' }])
      end

      it 'la ligne produit a vat_code 2' do
        revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
        expect(revenue_line.vat_code).to eq(2)
      end
    end
  end

  # -----------------------------------------------------------------------
  # PROPAGATION DES ANNOTATIONS ANALYTIQUES
  # -----------------------------------------------------------------------

  describe 'propagation des annotations analytiques vers les lignes d écriture' do
    let(:axis)             { create(:analytical_axis) }
    let(:analytical_acct)  { create(:analytical_account, analytical_axis: axis) }

    it 'propage les annotations de la ligne de facture vers la ligne d écriture (dépense)' do
      inv = create(:invoice, invoice_type: :supplier, partner: partner,
                   fiscal_year: fiscal_year, journal: purchase_journal)
      line = create(:invoice_line, invoice: inv, account: account_604,
                    quantity: 1, unit_price: '500.00', vat_rate: '21.00', position: 1)
      create(:invoice_line_annotation, invoice_line: line,
             analytical_axis: axis, analytical_account: analytical_acct)
      inv.compute_totals
      inv.save!
      Accounting::PostInvoice.call(invoice: inv)
      inv.reload

      expense_line = inv.journal_entry.lines.find { |l| l.account == account_604 }
      expect(expense_line.analytical_annotations.count).to eq(1)
      expect(expense_line.analytical_annotations.first.analytical_account).to eq(analytical_acct)
    end

    it 'ne propage pas les annotations sur les lignes TVA ni la contrepartie' do
      inv = create(:invoice, invoice_type: :supplier, partner: partner,
                   fiscal_year: fiscal_year, journal: purchase_journal)
      line = create(:invoice_line, invoice: inv, account: account_604,
                    quantity: 1, unit_price: '500.00', vat_rate: '21.00', position: 1)
      create(:invoice_line_annotation, invoice_line: line,
             analytical_axis: axis, analytical_account: analytical_acct)
      inv.compute_totals
      inv.save!
      Accounting::PostInvoice.call(invoice: inv)
      inv.reload

      vat_line     = inv.journal_entry.lines.find { |l| l.account == account_411 }
      payable_line = inv.journal_entry.lines.find { |l| l.account == account_440 }
      expect(vat_line.analytical_annotations).to be_empty
      expect(payable_line.analytical_annotations).to be_empty
    end
  end
end

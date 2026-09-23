require 'rails_helper'

RSpec.describe Accounting::Actions::GenerateInvoiceJournalEntry, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:sale_journal)     { create(:journal, :sale) }
  let(:partner)           { create(:partner) }

  def post_invoice_with_lines(type:, journal:, lines_data:, vat_treatment: :domestic, invoice_partner: partner)
    inv = create(:invoice, invoice_type: type, partner: invoice_partner,
                 fiscal_year: fiscal_year, journal: journal, vat_treatment: vat_treatment)
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

      it 'la ligne dépense porte le montant HT en vat_amount (pour la grille 81)' do
        expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
        expect(expense_line.vat_amount).to eq(BigDecimal('1000.00'))
      end

      it 'la ligne TVA (410100) a vat_code 59' do
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

      it 'aucune ligne TVA (410100) n est créée' do
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

      it 'la ligne produit porte le montant HT en vat_amount (pour la grille 01)' do
        revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
        expect(revenue_line.vat_amount).to eq(BigDecimal('2000.00'))
      end

      it 'la ligne TVA (450100) a vat_code 54' do
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

    context 'taux 0% (exonéré/exporté)' do
      subject(:invoice) do
        post_invoice_with_lines(type: :customer, journal: sale_journal,
                                lines_data: [{ account: account_700,
                                               unit_price: '500.00', vat_rate: '0.00' }])
      end

      it 'la ligne produit a vat_code 0 (grille 00)' do
        revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
        expect(revenue_line.vat_code).to eq(0)
      end

      it 'la ligne produit porte le montant HT en vat_amount (pour la grille 00)' do
        revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
        expect(revenue_line.vat_amount).to eq(BigDecimal('500.00'))
      end

      it 'aucune ligne TVA n est créée' do
        vat_lines = invoice.journal_entry.lines.select { |l| l.account == account_451 }
        expect(vat_lines).to be_empty
      end

      it "l écriture est équilibrée" do
        entry = invoice.journal_entry
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end
  end

  # -----------------------------------------------------------------------
  # FACTURE EN DEVISE ÉTRANGÈRE
  # -----------------------------------------------------------------------

  describe 'facture client en devise étrangère' do
    subject(:invoice) do
      inv = create(:invoice, invoice_type: :customer, partner: partner,
                   fiscal_year: fiscal_year, journal: sale_journal,
                   currency: 'USD', exchange_rate: '0.92')
      create(:invoice_line, invoice: inv, account: account_700,
             quantity: 1, unit_price: '1000.00', vat_rate: '21.00', position: 1)
      inv.compute_totals
      inv.save!
      Accounting::PostInvoice.call(invoice: inv)
      inv.reload
    end

    it "convertit la ligne client (400000) en EUR au taux de la facture" do
      receivable_line = invoice.journal_entry.lines.find { |l| l.account == account_400 }
      expect(receivable_line.debit).to eq(BigDecimal('1113.20'))
    end

    it 'stocke le montant original en devise facture sur amount_currency' do
      receivable_line = invoice.journal_entry.lines.find { |l| l.account == account_400 }
      expect(receivable_line.amount_currency).to eq(BigDecimal('1210.00'))
    end

    it 'stocke la devise et le taux de change sur la ligne' do
      receivable_line = invoice.journal_entry.lines.find { |l| l.account == account_400 }
      expect(receivable_line.currency).to eq('USD')
      expect(receivable_line.exchange_rate).to eq(BigDecimal('0.92'))
    end

    it 'convertit aussi les lignes produit et TVA en EUR' do
      revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
      vat_line     = invoice.journal_entry.lines.find { |l| l.account == account_451 }
      expect(revenue_line.credit).to eq(BigDecimal('920.00'))
      expect(vat_line.credit).to eq(BigDecimal('193.20'))
    end

    it "l'écriture reste équilibrée en EUR" do
      entry = invoice.journal_entry
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
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

  # -----------------------------------------------------------------------
  # RÉGIME COCONTRACTANT / AUTOLIQUIDATION
  # -----------------------------------------------------------------------

  describe 'facture client en régime non-domestic (le partenaire s auto-liquide, ou rien n est dû)' do
    let(:eu_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }

    subject(:invoice) do
      post_invoice_with_lines(type: :customer, journal: sale_journal, invoice_partner: eu_partner,
                              vat_treatment: :intracom_services,
                              lines_data: [{ account: account_700, unit_price: '1000.00', vat_rate: '21.00' }])
    end

    it 'la ligne produit porte la grille 47 (services intracommunautaires)' do
      revenue_line = invoice.journal_entry.lines.find { |l| l.account == account_700 }
      expect(revenue_line.vat_code).to eq(47)
    end

    it 'aucune ligne de TVA n est postée (le client s auto-liquide)' do
      vat_lines = invoice.journal_entry.lines.select { |l| l.account == account_451 }
      expect(vat_lines).to be_empty
    end

    it 'la ligne client (400000) ne porte que le montant HT' do
      receivable_line = invoice.journal_entry.lines.find { |l| l.account == account_400 }
      expect(receivable_line.debit).to eq(BigDecimal('1000.00'))
    end

    it "l écriture est équilibrée" do
      entry = invoice.journal_entry
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end
  end

  describe 'facture fournisseur en régime cocontractant (auto-liquidation par l entité)' do
    let(:eu_partner) { create(:partner, vat_number: 'DE123456789', country: 'DE') }

    subject(:invoice) do
      post_invoice_with_lines(type: :supplier, journal: purchase_journal, invoice_partner: eu_partner,
                              vat_treatment: :intracom_services,
                              lines_data: [{ account: account_604, unit_price: '1000.00', vat_rate: '21.00' }])
    end

    it 'la ligne dépense porte la grille 87 (services reçus en autoliquidation)' do
      expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
      expect(expense_line.vat_code).to eq(87)
    end

    it 'la ligne fournisseur (440000) ne porte que le montant HT' do
      payable_line = invoice.journal_entry.lines.find { |l| l.account == account_440 }
      expect(payable_line.credit).to eq(BigDecimal('1000.00'))
    end

    it 'une ligne de TVA due (450100, grille 56) est postée au crédit' do
      due_line = invoice.journal_entry.lines.find { |l| l.account == account_451 }
      expect(due_line.vat_code).to eq(56)
      expect(due_line.credit).to eq(BigDecimal('210.00'))
    end

    it 'une ligne de TVA déductible (410100, grille 59) est postée au débit pour le même montant' do
      deductible_line = invoice.journal_entry.lines.find { |l| l.account == account_411 }
      expect(deductible_line.vat_code).to eq(59)
      expect(deductible_line.debit).to eq(BigDecimal('210.00'))
    end

    it "l écriture est équilibrée" do
      entry = invoice.journal_entry
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    context 'construction_reverse_charge' do
      subject(:invoice) do
        post_invoice_with_lines(type: :supplier, journal: purchase_journal, invoice_partner: eu_partner,
                                vat_treatment: :construction_reverse_charge,
                                lines_data: [{ account: account_604, unit_price: '500.00', vat_rate: '21.00' }])
      end

      it 'la ligne dépense porte la grille 88' do
        expense_line = invoice.journal_entry.lines.find { |l| l.account == account_604 }
        expect(expense_line.vat_code).to eq(88)
      end

      it 'la ligne de TVA due porte la grille 57' do
        due_line = invoice.journal_entry.lines.find { |l| l.account == account_451 }
        expect(due_line.vat_code).to eq(57)
      end
    end
  end
end

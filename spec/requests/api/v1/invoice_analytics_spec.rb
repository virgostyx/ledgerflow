require 'rails_helper'

# A BudgetFlow invoice names its project and its budget line (sub line); every line is annotated with the matching analytical
# accounts, which the caller created through PUT /projects/:ref (docs/dev/api/inbound-api.md).
RSpec.describe 'Api::V1 invoice analytical accounts', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let!(:proj_axis) { Accounting::AnalyticalAxis.find_or_create_by!(code: 'PROJ') { |a| a.label_fr = 'Projects' } }
  let!(:budg_axis) { Accounting::AnalyticalAxis.find_or_create_by!(code: 'BUDG') { |a| a.label_fr = 'Budget lines' } }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write analytical:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:lines) do
    [ { account_code: '604000', description: 'Consulting', quantity: '2', unit_price: '50.00', vat_rate: '21' },
      { account_code: '604000', description: 'Travel', quantity: '1', unit_price: '10.00', vat_rate: '0' } ]
  end
  let(:payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, post: false, lines: lines,
      project_ref: 'bf-project-1', budget_line_ref: 'bf-subline-5' }
  end

  def put_structure(body = { code: 'PRODEM', name: 'PRODEM ZAMBIA', budget_lines: [ { ref: 'bf-subline-5', code: '1.1.1', label: 'Staff' },
                                                                                  { ref: 'bf-subline-6', code: '1.1.2', label: 'Driver' } ] },
                    ref: 'bf-project-1')
    put("/api/v1/projects/#{ref}", params: body, headers: headers, as: :json)
  end

  def put_invoice(body = payload, ref: 'BF-I-1') = put("/api/v1/invoices/#{ref}", params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def invoice(ref = 'BF-I-1') = Accounting::Invoice.external.find_by(external_ref: ref)
  def annotated(inv) = inv.lines.map { |l| l.analytical_annotations.map { |a| [ a.analytical_axis.code, a.analytical_account.external_ref ] }.sort }

  context 'when the project and its budget are known' do
    before { put_structure }

    it 'annotates every line with the project and the budget line' do
      put_invoice

      expect(response).to have_http_status(:created)
      expect(annotated(invoice)).to eq([ [ %w[BUDG bf-subline-5], %w[PROJ bf-project-1] ] ] * 2)
    end

    it 'carries the annotations to the entry when the invoice is posted at once' do
      put_invoice(payload.except(:post))

      expect(response).to have_http_status(:created)
      expense = invoice.journal_entry.lines.select { |l| l.account.code == '604000' }
      expect(expense.flat_map { |l| l.analytical_annotations.map { |a| a.analytical_account.external_ref } }).to match_array(%w[bf-project-1 bf-subline-5] * 2)
    end

    it 'is idempotent' do
      put_invoice
      put_invoice

      expect(response).to have_http_status(:ok)
      expect(Accounting::InvoiceLineAnnotation.count).to eq(4)
    end

    it 'moves an untouched draft to another budget line in place' do
      put_invoice
      put_invoice(payload.merge(budget_line_ref: 'bf-subline-6'))

      expect(response).to have_http_status(:ok)
      expect(annotated(invoice)).to eq([ [ %w[BUDG bf-subline-6], %w[PROJ bf-project-1] ] ] * 2)
    end

    it 'refuses to correct a draft whose annotations the accountant changed' do
      put_invoice
      invoice.lines.first.analytical_annotations.find_by(analytical_axis: budg_axis).update!(analytical_account: Accounting::AnalyticalAccount.find_by!(external_ref: 'bf-subline-6'))

      put_invoice(payload.merge(budget_line_ref: 'bf-subline-6'))

      expect(response).to have_http_status(:conflict)
    end

    it 'refuses a budget line of another project' do
      put_structure({ code: 'OTHER', name: 'Other', budget_lines: [ { ref: 'bf-subline-90', code: '1.1.1', label: 'x' } ] }, ref: 'bf-project-2')

      expect { put_invoice(payload.merge(budget_line_ref: 'bf-subline-90')) }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['budget_line_ref'].first).to include('another project')
    end

    it 'refuses a closed project, saying so' do
      put_structure({ code: 'PRODEM', name: 'PRODEM ZAMBIA', active: false, budget_lines: [ { ref: 'bf-subline-5', code: '1.1.1', label: 'Staff' } ] })

      expect { put_invoice }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['project_ref'].first).to include('not active')
    end
  end

  context 'when the structure is not there yet' do
    it 'refuses an unknown project and writes nothing' do
      expect { put_invoice }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['project_ref'].first).to include('bf-project-1').and include('not synchronised')
    end

    it 'refuses an unknown budget line of a known project' do
      put_structure({ code: 'PRODEM', name: 'PRODEM ZAMBIA', budget_lines: [] })

      put_invoice

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['budget_line_ref'].first).to include('bf-subline-5').and include('not synchronised')
    end
  end

  it 'keeps working without any reference (older callers): no annotation' do
    put_invoice(payload.except(:project_ref, :budget_line_ref))

    expect(response).to have_http_status(:created)
    expect(Accounting::InvoiceLineAnnotation.count).to eq(0)
  end
end

require 'rails_helper'

# BudgetFlow keeps the analytical accounts of its projects and budget lines (docs/dev/api/inbound-api.md): one on the axis PROJ for
# the project, one on the axis BUDG for each sub line, all addressed by the caller's own references.
RSpec.describe 'Api::V1::AnalyticalProjects', type: :request do
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:proj_axis) { Accounting::AnalyticalAxis.find_or_create_by!(code: 'PROJ') { |a| a.label_fr = 'Projects' } }
  let!(:budg_axis) { Accounting::AnalyticalAxis.find_or_create_by!(code: 'BUDG') { |a| a.label_fr = 'Budget lines' } }

  let(:scopes)  { %w[analytical:write] }
  let(:issued)  { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:payload) do
    { code: 'PRODEM', name: 'PRODEM ZAMBIA', active: true,
      budget_lines: [ { ref: 'bf-subline-5', code: '1.1.1', label: '1 Staff > 1.1 Salaries > 1.1.1 Coordinator' },
                      { ref: 'bf-subline-6', code: '1.1.2', label: '1 Staff > 1.1 Salaries > 1.1.2 Driver' } ] }
  end

  def put_project(body = payload, ref: 'bf-project-1') = put("/api/v1/projects/#{ref}", params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def account(ref) = Accounting::AnalyticalAccount.find_by(external_ref: ref)

  it 'creates the project account and one account per sub line, each under the right axis' do
    expect { put_project }.to change(Accounting::AnalyticalAccount, :count).by(3)

    expect(response).to have_http_status(:created)
    expect(account('bf-project-1')).to have_attributes(analytical_axis: proj_axis, code: 'PRODEM', label_fr: 'PRODEM ZAMBIA', active: true, external_group: 'bf-project-1')
    expect(account('bf-subline-5')).to have_attributes(analytical_axis: budg_axis, code: 'PRODEM-1.1.1', label_fr: '1 Staff > 1.1 Salaries > 1.1.1 Coordinator',
                                                       active: true, external_group: 'bf-project-1')
    expect(json).to include('ref' => 'bf-project-1', 'code' => 'PRODEM')
    expect(json['budget_lines'].map { |l| l['code'] }).to eq(%w[PRODEM-1.1.1 PRODEM-1.1.2])
    expect(json['budget_lines'].first).to eq('ref' => 'bf-subline-5', 'code' => 'PRODEM-1.1.1', 'active' => true)
    expect(account('bf-subline-5')).to be_managed
  end

  it 'creates only the project account when the budget is not validated yet (no sub line)' do
    expect { put_project(payload.merge(budget_lines: [])) }.to change(Accounting::AnalyticalAccount, :count).by(1)

    expect(response).to have_http_status(:created)
  end

  it 'is idempotent: replaying changes nothing' do
    put_project
    expect { put_project }.not_to change(Accounting::AnalyticalAccount, :count)

    expect(response).to have_http_status(:ok)
  end

  it 'adds a sub line and renames one by reference, keeping the account' do
    put_project
    id = account('bf-subline-5').id

    put_project(payload.merge(budget_lines: payload[:budget_lines].map { |l| l[:ref] == 'bf-subline-5' ? l.merge(code: '1.1.9', label: 'Renamed') : l } +
                                            [ { ref: 'bf-subline-7', code: '2.1.1', label: 'Equipment' } ]))

    expect(response).to have_http_status(:ok)
    expect(account('bf-subline-5')).to have_attributes(id: id, code: 'PRODEM-1.1.9', label_fr: 'Renamed')
    expect(account('bf-subline-7')).to have_attributes(code: 'PRODEM-2.1.1', analytical_axis: budg_axis)
  end

  it 'follows a change of the project code on every sub line' do
    put_project
    put_project(payload.merge(code: 'PRODEM2'))

    expect(account('bf-project-1').code).to eq('PRODEM2')
    expect(account('bf-subline-6').code).to eq('PRODEM2-1.1.2')
  end

  it 'deactivates a sub line the project no longer has, and reactivates it if it comes back' do
    put_project
    put_project(payload.merge(budget_lines: payload[:budget_lines].first(1)))
    expect(account('bf-subline-6')).not_to be_active
    expect(account('bf-subline-5')).to be_active

    put_project
    expect(account('bf-subline-6')).to be_active
  end

  it 'deactivates the project and all its sub lines when it is not active (closed)' do
    put_project
    put_project(payload.merge(active: false))

    expect(Accounting::AnalyticalAccount.where(external_group: 'bf-project-1').pluck(:active)).to all(be(false))
  end

  it 'does not touch the sub lines of another project' do
    put_project
    put_project(payload.merge(code: 'OTHER', budget_lines: [ { ref: 'bf-subline-90', code: '1.1.1', label: 'x' } ]), ref: 'bf-project-2')

    expect(account('bf-subline-5')).to be_active
  end

  it 'refuses a code already used by an account BudgetFlow does not manage, and writes nothing' do
    create(:analytical_account, analytical_axis: proj_axis, code: 'PRODEM')

    expect { put_project }.not_to change(Accounting::AnalyticalAccount, :count)

    expect(response).to have_http_status(:conflict)
    expect(json['error']).to include('PRODEM')
  end

  it 'refuses a code too long for LedgerFlow, naming it, and writes nothing' do
    expect { put_project(payload.merge(code: 'P' * 38)) }.not_to change(Accounting::AnalyticalAccount, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors'].values.flatten.join).to include('too long')
  end

  it 'refuses a project without a code or a name' do
    put_project(payload.merge(code: ' '))
    expect(response).to have_http_status(:unprocessable_content)

    put_project(payload.merge(name: ''))
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'says so when the entity has no PROJ or BUDG axis' do
    budg_axis.destroy!

    put_project

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors'].values.flatten.join).to include('BUDG')
  end

  it 'needs the analytical:write permission' do
    issued.first.update!(scopes: %w[partners:write])

    put_project

    expect(response).to have_http_status(:forbidden)
  end
end

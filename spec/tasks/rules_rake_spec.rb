require 'rails_helper'
require 'rake'

RSpec.describe 'rules rake tasks' do
  include_context 'with entity'

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('rules:validate')
  end

  def run(task, *args)
    Rake::Task[task].reenable
    Rake::Task[task].invoke(*args.map(&:to_s))
  end

  let(:args) { [ entity.id, 'vat_declaration', 'Jane Doe', 'Chartered accountant, Doe & Co', 'letter of 2026-10-30' ] }

  it 'rules:validate records an accountant validation of a rule' do
    expect { run('rules:validate', *args) }
      .to output(/vat_declaration validated by Jane Doe/).to_stdout
      .and change { ActsAsTenant.with_tenant(entity) { Accounting::RuleValidation.validated?('vat_declaration') } }.from(false).to(true)
  end

  it 'rules:revoke withdraws it' do
    run('rules:validate', *args)
    expect { run('rules:revoke', entity.id, 'vat_declaration') }
      .to change { ActsAsTenant.with_tenant(entity) { Accounting::RuleValidation.validated?('vat_declaration') } }.from(true).to(false)
  end

  it 'rules:validate refuses an unknown rule, writing nothing' do
    expect { run('rules:validate', entity.id, 'nope', 'Jane', 'CPA', 'ref') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end

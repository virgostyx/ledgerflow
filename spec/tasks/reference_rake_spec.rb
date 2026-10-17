require "rails_helper"
require "rake"

# Production runs no seeds: the data of the law and of ISO (VAT codes and grids, currencies) is loaded by reference:load, at every start, without ever duplicating.
RSpec.describe "reference:load" do
  before(:all) do
    Rake.application.rake_require("tasks/reference", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
  end

  def run_task
    task = Rake::Task["reference:load"]
    task.reenable
    previous = $stdout
    $stdout = StringIO.new
    task.invoke
  ensure
    $stdout = previous
  end

  it "loads the VAT codes and the currencies of an empty database" do
    [ Accounting::VatGridMapping, Accounting::VatAccountGridRule, Accounting::VatCode ].each(&:delete_all)
    Accounting::Currency.delete_all
    run_task
    expect(Accounting::VatCode.count).to be >= 13
    expect(Accounting::Currency.where(code: %w[EUR USD GBP]).count).to eq(3)
  end

  it "changes nothing the second time" do
    run_task
    counts = [ Accounting::VatCode.count, Accounting::VatGridMapping.count, Accounting::Currency.count ]
    run_task
    expect([ Accounting::VatCode.count, Accounting::VatGridMapping.count, Accounting::Currency.count ]).to eq(counts)
  end

  it "is run at every start of the container, after the databases are prepared" do
    entrypoint = Rails.root.join("bin/docker-entrypoint").read
    expect(entrypoint.index("db:prepare")).to be < entrypoint.index("reference:load")
  end
end

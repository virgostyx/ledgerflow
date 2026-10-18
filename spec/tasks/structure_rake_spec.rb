require "rails_helper"
require "rake"
require "tmpdir"

# Production runs PostgreSQL 16 (like the development container), but a workstation with a newer pg_dump writes settings that 16 rejects
# (`SET transaction_timeout`, PostgreSQL 17+): db:prepare then aborts at the first start. The dump is made portable after every dump.
RSpec.describe "db:structure:portable" do
  before(:all) do
    Rake.application.rake_require("tasks/structure", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
  end

  it "removes the settings that PostgreSQL 16 does not know and keeps the rest" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "structure.sql")
      File.write(path, "SET lock_timeout = 0;\nSET transaction_timeout = 0;\nSET client_encoding = 'UTF8';\nCREATE TABLE t (id bigint);\n")
      task = Rake::Task["db:structure:portable"]
      task.reenable
      task.invoke(path)
      expect(File.read(path)).to eq("SET lock_timeout = 0;\nSET client_encoding = 'UTF8';\nCREATE TABLE t (id bigint);\n")
    end
  end

  it "runs after every dump of the structure" do
    # a child process loads all the tasks of Rails once; the dump has its own action plus ours
    script = 'Rails.application.load_tasks; puts Rake::Task["db:schema:dump"].actions.size'
    output = IO.popen({ "RAILS_ENV" => "test" }, [ "bin/rails", "runner", script ], chdir: Rails.root.to_s, err: File::NULL, &:read)
    expect(output.to_i).to be >= 2
  end

  it "leaves the committed structure loadable by PostgreSQL 16" do
    expect(Rails.root.join("db/structure.sql").read).not_to match(/transaction_timeout/)
  end
end

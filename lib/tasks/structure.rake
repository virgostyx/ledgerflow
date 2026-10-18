# The production database is PostgreSQL 16; a pg_dump of version 17 or later writes `SET transaction_timeout`, which 16 rejects (db:prepare aborts at the first start).
namespace :db do
  namespace :structure do
    desc "Removes from db/structure.sql the settings PostgreSQL 16 does not know"
    task :portable, [ :path ] do |_task, args|
      path = args[:path] || Rails.root.join("db/structure.sql").to_s
      next unless File.exist?(path)

      File.write(path, File.read(path).gsub(/^SET transaction_timeout = 0;\n/, ""))
    end
  end
end

Rake::Task["db:schema:dump"].enhance { Rake::Task["db:structure:portable"].invoke } if Rake::Task.task_defined?("db:schema:dump")

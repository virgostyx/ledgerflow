namespace :ledger do
  desc "Bulk-generate N balanced journal entries on the reference ledger for performance testing: ledger:generate[200000]"
  task :generate, [ :count ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    count = Integer(args.fetch(:count, 1000))
    entity = ActsAsTenant.without_tenant { Entity.find_by!(name: Seeders::ReferenceLedgerSeeder::ENTITY_NAME) }

    ActsAsTenant.with_tenant(entity) do
      journal        = Accounting::Journal.find_by!(code: "OD")
      fiscal_year    = Accounting::FiscalYear.find_by!(year: 2026)
      expense        = Accounting::Account.find_by!(code: Seeders::ReferenceLedgerSeeder::EXPENSE)
      payable        = Accounting::Account.find_by!(code: Seeders::ReferenceLedgerSeeder::SUPPLIERS)
      days_span      = (fiscal_year.end_date - fiscal_year.start_date).to_i

      # Raw bulk SQL — 200k AR-object creates (with callbacks/validations) would take
      # minutes; report performance targets (docs/dev/reports/spec.md §2.4) are about
      # querying this volume, not about how it got seeded.
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET CONSTRAINTS ALL DEFERRED")
        ApplicationRecord.connection.execute(<<~SQL)
          WITH new_entries AS (
            INSERT INTO accounting_journal_entries
              (entity_id, journal_id, fiscal_year_id, entry_date, reference, description, status, created_at, updated_at)
            SELECT
              #{entity.id}, #{journal.id}, #{fiscal_year.id},
              DATE '#{fiscal_year.start_date}' + (n % #{days_span}),
              'GEN#{fiscal_year.year}/' || lpad(n::text, 6, '0'),
              'Generated performance entry ' || n,
              1, now(), now()
            FROM generate_series(1, #{count}) AS n
            RETURNING id, entity_id, entry_date
          )
          INSERT INTO accounting_journal_entry_lines
            (entity_id, journal_entry_id, account_id, debit, credit, label, currency, entry_date, amount_residual, sort_order, created_at, updated_at)
          SELECT entity_id, id, #{expense.id}, 10.00, 0,    'Generated', 'EUR', entry_date, 10.00, 0, now(), now() FROM new_entries
          UNION ALL
          SELECT entity_id, id, #{payable.id}, 0,    10.00, 'Generated', 'EUR', entry_date, 10.00, 0, now(), now() FROM new_entries
        SQL
      end
    end

    puts "[ledger:generate] #{count} entries (#{count * 2} lines) generated on '#{entity.name}'."
  end
end

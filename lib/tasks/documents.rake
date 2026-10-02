namespace :documents do
  desc "Recompute the SHA-256 of every stored document and name those whose file no longer matches (ENTITY_ID=n to limit)"
  task verify: :environment do
    failed = false
    Accounting::VerifyDocumentsJob.sweep(ENV["ENTITY_ID"].presence).each do |entity, result|
      puts "[documents] #{entity.name}: #{result[:checked]} documents checked, #{result[:failures].size} failed#{", #{result[:errors]} could not be read" if result[:errors].positive?}"
      result[:failures].each do |document, status|
        failed = true
        puts "[documents]   #{document.name}: #{status} (document ##{document.id})"
      end
    end
    exit(1) if failed
  end

  desc "Bring the UBL and PDF kept on invoices (Peppol, BudgetFlow) into the document store, once (ENTITY_ID=n to limit)"
  task import_invoice_attachments: :environment do
    entities = ENV["ENTITY_ID"].present? ? Entity.where(id: ENV["ENTITY_ID"]) : Entity.all
    entities.find_each do |entity|
      next unless entity.feature?(:f03)

      result = ActsAsTenant.with_tenant(entity) { Accounting::ImportInvoiceAttachments.call }
      puts "[documents] #{entity.name}: #{result[:imported]} imported, #{result[:refused].size} refused"
      result[:refused].each { |line| puts "[documents]   #{line}" }
    end
  end
end

namespace :bank do
  desc "Simulate the bank booking a generated payment batch: bank:pay_batch[BATCH_ID]"
  task :pay_batch, [ :id ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    batch = ActsAsTenant.without_tenant { Accounting::PaymentBatch.find(args.fetch(:id)) }
    ActsAsTenant.with_tenant(batch.entity) do
      xml = begin
        Bank::Simulator::PayBatch.call(payment_batch: batch)
      rescue ArgumentError => e
        abort e.message
      end
      result = Accounting::ImportCamtStatement.call(xml: xml, bank_account: batch.bank_account)
      abort result.message if result.failure?
      puts "Imported #{result[:imported_count]} transaction(s)"
    end
  end

  desc "Simulate a customer paying an invoice: bank:receipt[INVOICE_ID,BANK_ACCOUNT_ID,AMOUNT]"
  task :receipt, [ :invoice_id, :bank_account_id, :amount ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    invoice = ActsAsTenant.without_tenant { Accounting::Invoice.find(args.fetch(:invoice_id)) }
    ActsAsTenant.with_tenant(invoice.entity) do
      bank_account = Accounting::BankAccount.find(args.fetch(:bank_account_id))
      xml = begin
        Bank::Simulator::CustomerReceipt.call(
          invoice: invoice, bank_account: bank_account, amount: args[:amount]&.then { |a| BigDecimal(a) }
        )
      rescue ArgumentError => e
        abort e.message
      end
      result = Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
      abort result.message if result.failure?
      puts "Imported #{result[:imported_count]} transaction(s)"
    end
  end

  desc "Simulate one customer transfer settling several invoices: bank:grouped_receipt[BANK_ACCOUNT_ID,'ID ID ...']"
  task :grouped_receipt, [ :bank_account_id, :invoice_ids ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    bank_account = ActsAsTenant.without_tenant { Accounting::BankAccount.find(args.fetch(:bank_account_id)) }
    ActsAsTenant.with_tenant(bank_account.entity) do
      invoices = Accounting::Invoice.find(args.fetch(:invoice_ids).split)
      xml = begin
        Bank::Simulator::GroupedReceipt.call(invoices: invoices, bank_account: bank_account)
      rescue ArgumentError => e
        abort e.message
      end
      result = Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
      abort result.message if result.failure?
      puts "Imported #{result[:imported_count]} transaction(s)"
    end
  end

  desc "Simulate the bank debiting its fees: bank:fees[BANK_ACCOUNT_ID,AMOUNT] (default 4.50)"
  task :fees, [ :bank_account_id, :amount ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    bank_account = ActsAsTenant.without_tenant { Accounting::BankAccount.find(args.fetch(:bank_account_id)) }
    ActsAsTenant.with_tenant(bank_account.entity) do
      options = { bank_account: bank_account }
      options[:amount] = BigDecimal(args[:amount]) if args[:amount]
      result = Accounting::ImportCamtStatement.call(xml: Bank::Simulator::BankFees.call(**options), bank_account: bank_account)
      abort result.message if result.failure?
      puts "Imported #{result[:imported_count]} transaction(s)"
    end
  end

  desc "Simulate an unidentified incoming transfer (no reference), to try manual allocation: bank:transfer[BANK_ACCOUNT_ID,AMOUNT]"
  task :transfer, [ :bank_account_id, :amount ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    bank_account = ActsAsTenant.without_tenant { Accounting::BankAccount.find(args.fetch(:bank_account_id)) }
    ActsAsTenant.with_tenant(bank_account.entity) do
      xml = Bank::Simulator::BuildStatement.call(
        iban: bank_account.iban,
        entries: [ { date: Date.current, amount: BigDecimal(args.fetch(:amount)), description: "Transfer" } ]
      )
      result = Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
      abort result.message if result.failure?
      puts "Imported #{result[:imported_count]} transaction(s)"
    end
  end
end

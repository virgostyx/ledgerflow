namespace :bank do
  desc "Simulate the bank booking a generated payment batch: bank:pay_batch[BATCH_ID]"
  task :pay_batch, [ :id ] => :environment do |_, args|
    abort "Development/test only" if Rails.env.production?

    batch = ActsAsTenant.without_tenant { Accounting::PaymentBatch.find(args.fetch(:id)) }
    ActsAsTenant.with_tenant(batch.entity) do
      result = Accounting::ImportCamtStatement.call(
        xml: Bank::Simulator::PayBatch.call(payment_batch: batch), bank_account: batch.bank_account
      )
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
      xml = Bank::Simulator::CustomerReceipt.call(
        invoice: invoice, bank_account: bank_account, amount: args[:amount]&.then { |a| BigDecimal(a) }
      )
      result = Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
      abort result.message if result.failure?
      puts "Imported #{result[:imported_count]} transaction(s)"
    end
  end
end

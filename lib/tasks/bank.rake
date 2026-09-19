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
end

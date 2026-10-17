# The reference data every company needs and that belongs to no company: the VAT codes and grids (VAT law) and the currencies (ISO 4217). Production runs no seeds; this is
# idempotent (find or create) and runs at every start of the container (bin/docker-entrypoint).
namespace :reference do
  desc "Loads the VAT codes and grids and the currencies, without duplicating"
  task load: :environment do
    Seeders::VatCodesSeeder.call
    Seeders::CurrenciesSeeder.call
  end
end

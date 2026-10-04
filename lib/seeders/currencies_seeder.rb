# ISO 4217 currencies with their number of decimals (F11): global reference data, not tenant-scoped. 2 decimals unless listed.
module Seeders
  class CurrenciesSeeder
    ZERO_DECIMALS  = %w[BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX VND VUV XAF XOF XPF].freeze
    THREE_DECIMALS = %w[BHD IQD JOD KWD LYD OMR TND].freeze

    def self.call
      Accounting::MoneyPresenter::SUPPORTED_CURRENCIES.each do |code|
        decimals = ZERO_DECIMALS.include?(code) ? 0 : (THREE_DECIMALS.include?(code) ? 3 : 2)
        Accounting::Currency.find_or_create_by!(code: code) { |currency| currency.decimals = decimals }
      end
    end
  end
end

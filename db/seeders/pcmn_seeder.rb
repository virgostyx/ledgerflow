require 'json'

module Seeders
  class PcmnSeeder
    SEED_FILE = Rails.root.join('db/seeds/pcmn_asbl.json')

    def self.call
      new.call
    end

    def call
      data = JSON.parse(File.read(SEED_FILE))
      counts = { created: 0, skipped: 0 }

      data.each do |attrs|
        record = Accounting::Account.find_or_initialize_by(code: attrs['code'])
        if record.new_record?
          record.assign_attributes(attrs.slice('label_fr', 'account_class',
                                               'account_type', 'normal_balance',
                                               'is_leaf', 'reconcilable'))
          record.save!
          counts[:created] += 1
        else
          counts[:skipped] += 1
        end
      end

      puts "[PCMN] #{counts[:created]} comptes créés, #{counts[:skipped]} déjà présents."
    end
  end
end

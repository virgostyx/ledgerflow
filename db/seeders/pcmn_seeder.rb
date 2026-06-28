require "json"

module Seeders
  class PcmnSeeder
    ASBL_LEGAL_FORMS = %w[ASBL Fondation].freeze

    SEED_FILES = {
      asbl:       Rails.root.join("db/seeds/pcmn_asbl.json"),
      commercial: Rails.root.join("db/seeds/pcmn_commercial.json")
    }.freeze

    def self.call(entity: nil)
      new(entity).call
    end

    def initialize(entity)
      type = ASBL_LEGAL_FORMS.include?(entity&.legal_form) ? :asbl : :commercial
      @file = SEED_FILES[type]
    end

    def call
      data = JSON.parse(File.read(@file))
      counts = { created: 0, skipped: 0 }

      data.each do |attrs|
        record = Accounting::Account.find_or_initialize_by(code: attrs["code"])
        if record.new_record?
          record.assign_attributes(attrs.slice("label_fr", "account_class",
                                               "account_type", "normal_balance",
                                               "is_leaf", "reconcilable"))
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

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

    # The accounts that carry the result of a closed year, in the chart of the associations (the companies' ones are the defaults of the entity)
    ASBL_CARRY = { closing_carry_account_code: "120100", closing_loss_account_code: "120200" }.freeze

    def initialize(entity)
      @entity = entity
      @type = ASBL_LEGAL_FORMS.include?(entity&.legal_form) ? :asbl : :commercial
      @file = SEED_FILES[@type]
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

      use_the_carry_accounts_of_the_chart
      puts "[PCMN] #{counts[:created]} comptes créés, #{counts[:skipped]} déjà présents."
    end

    private

    # An association carries its result to 120100 / 120200, not to the 140100 / 140200 of the companies: only while the entity still has the defaults.
    def use_the_carry_accounts_of_the_chart
      return unless @type == :asbl && @entity&.persisted?
      return unless @entity.closing_carry_account_code == "140100" && @entity.closing_loss_account_code == "140200"

      @entity.update!(ASBL_CARRY)
    end
  end
end

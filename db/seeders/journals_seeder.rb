module Seeders
  class JournalsSeeder
    JOURNALS = [
      { code: 'ACH',   label_fr: 'Achats',              journal_type: :purchase, sequence_prefix: 'ACH',   default_account_code: '440100' },
      { code: 'VTE',   label_fr: 'Ventes',              journal_type: :sale,     sequence_prefix: 'VTE',   default_account_code: '400100' },
      { code: 'BNQ',   label_fr: 'Banque',              journal_type: :bank,     sequence_prefix: 'BNQ',   default_account_code: '550100' },
      { code: 'CAISS', label_fr: 'Caisse',              journal_type: :cash,     sequence_prefix: 'CAI',   default_account_code: '570100' },
      { code: 'OD',    label_fr: 'Opérations diverses', journal_type: :misc,     sequence_prefix: 'OD',    default_account_code: nil },
      { code: 'SAL',   label_fr: 'Salaires',            journal_type: :payroll,  sequence_prefix: 'SAL',   default_account_code: nil }
    ].freeze

    def self.call
      new.call
    end

    def call
      counts = { created: 0, skipped: 0 }

      JOURNALS.each do |attrs|
        record = Accounting::Journal.find_or_initialize_by(code: attrs[:code])
        if record.new_record?
          account_code = attrs[:default_account_code]
          default_account = account_code ? Accounting::Account.find_by(code: account_code) : nil
          record.assign_attributes(attrs.except(:default_account_code))
          record.default_account = default_account if default_account
          record.save!
          counts[:created] += 1
        else
          counts[:skipped] += 1
        end
      end

      puts "[Journals] #{counts[:created]} journaux créés, #{counts[:skipped]} déjà présents."
    end
  end
end

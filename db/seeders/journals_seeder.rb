module Seeders
  class JournalsSeeder
    JOURNALS = [
      { code: 'ACH', label_fr: 'Achats',            journal_type: :purchase, sequence_prefix: 'ACH' },
      { code: 'VTE', label_fr: 'Ventes',             journal_type: :sale,     sequence_prefix: 'VTE' },
      { code: 'BNQ', label_fr: 'Banque',             journal_type: :bank,     sequence_prefix: 'BNQ' },
      { code: 'CAISS', label_fr: 'Caisse',           journal_type: :cash,     sequence_prefix: 'CAI' },
      { code: 'OD',  label_fr: 'Opérations diverses', journal_type: :misc,    sequence_prefix: 'OD'  },
      { code: 'SAL', label_fr: 'Salaires',           journal_type: :payroll,  sequence_prefix: 'SAL' }
    ].freeze

    def self.call
      new.call
    end

    def call
      counts = { created: 0, skipped: 0 }

      JOURNALS.each do |attrs|
        record = Accounting::Journal.find_or_initialize_by(code: attrs[:code])
        if record.new_record?
          record.assign_attributes(attrs)
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

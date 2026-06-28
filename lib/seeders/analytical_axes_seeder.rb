module Seeders
  class AnalyticalAxesSeeder
    AXES = [
      { code: "PROJ", label_fr: "Projects/Programmes",    label_nl: "Projecten/Programma's" },
      { code: "ACT",  label_fr: "Activities",             label_nl: "Activiteiten" },
      { code: "FIN",  label_fr: "Funding Sources",        label_nl: "Financieringsbronnen" },
      { code: "BUDG", label_fr: "Budget Lines",           label_nl: "Budgetlijnen" }
    ].freeze

    def self.call
      new.call
    end

    def call
      counts = { created: 0, skipped: 0 }

      AXES.each do |attrs|
        record = Accounting::AnalyticalAxis.find_or_initialize_by(code: attrs[:code])
        if record.new_record?
          record.assign_attributes(attrs)
          record.save!
          counts[:created] += 1
        else
          counts[:skipped] += 1
        end
      end

      puts "[AnalyticalAxes] #{counts[:created]} axes created, #{counts[:skipped]} already present."
    end
  end
end

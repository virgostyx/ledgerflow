FactoryBot.define do
  factory :analytical_annotation, class: "Accounting::AnalyticalAnnotation" do
    association :analytical_axis
    association :analytical_account

    # journal_entry_line can be passed explicitly; otherwise a debit line is built
    # with the double-entry constraint deferred so a single line can be inserted.
    before(:create) do |annotation|
      next if annotation.journal_entry_line.present?

      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = create(:journal_entry)
      annotation.journal_entry_line = create(:journal_entry_line, :debit, journal_entry: entry)
    end
  end
end

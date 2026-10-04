# F07: the example entry templates (rent, annual insurance with a deferred charge, depreciation, bank charges, VAT regularisation), for
# the entity that has the accounts they use (an example whose account is missing is left out). Idempotent. => number added
class Accounting::SeedEntryTemplates
  EXAMPLES = [
    { name: "Rent", description: "Rent {mois} {année}",
      lines: [ [ "610100", :debit, :percent, 100, "Rent {mois} {année}" ], [ "440000", :credit, :percent, 100, "Landlord {mois} {année}" ] ] },
    { name: "Annual insurance with a deferred charge", description: "Insurance premium {année}",
      lines: [ [ "610400", :debit, :input, nil, "Premium of the year" ], [ "490100", :debit, :input, nil, "Deferred charge" ],
               [ "440000", :credit, :percent, 100, "Insurer" ] ] },
    { name: "Depreciation", description: "Depreciation {période}",
      lines: [ [ "630200", :debit, :percent, 100, "Depreciation {période}" ], [ "249000", :credit, :percent, 100, "Accumulated depreciation" ] ] },
    { name: "Bank charges", description: "Bank charges {période}",
      lines: [ [ "651100", :debit, :percent, 100, "Bank charges {période}" ], [ "550100", :credit, :percent, 100, "Bank" ] ] },
    { name: "VAT regularisation", description: "VAT regularisation {période}",
      lines: [ [ "450100", :debit, :percent, 100, "VAT payable" ], [ "410100", :credit, :percent, 100, "VAT recoverable" ] ] }
  ].freeze

  def self.call
    journal = Accounting::Journal.find_by(journal_type: :misc, active: true)
    return 0 unless journal

    EXAMPLES.count do |example|
      next false if Accounting::EntryTemplate.exists?(name: example[:name])

      accounts = example[:lines].map { |code, *| Accounting::Account.active.find_by(code: code) }
      next false if accounts.any?(&:nil?)

      template = Accounting::EntryTemplate.new(name: example[:name], description: example[:description], journal: journal)
      example[:lines].zip(accounts).each_with_index do |((_, side, kind, percentage, label), account), i|
        template.lines.build(account: account, side: side, amount_kind: kind, percentage: percentage, label: label, position: i)
      end
      template.save!
      true
    end
  end
end

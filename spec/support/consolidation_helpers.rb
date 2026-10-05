# F12b: companies with books, and a group of them, for the consolidation specs. Each company keeps its own books in its own tenant, as in production.
module ConsolidationHelpers
  DATE = Date.new(2026, 12, 31)
  # code => [account_type, normal_balance, class, reconcilable]
  CHART = {
    "100000" => [ :equity, :credit, 1, false ], "170000" => [ :liability, :credit, 1, false ], "290000" => [ :asset, :debit, 2, false ], "400000" => [ :asset, :debit, 4, true ],
    "440000" => [ :liability, :credit, 4, true ], "550000" => [ :asset, :debit, 5, false ], "610000" => [ :expense, :debit, 6, false ], "700000" => [ :revenue, :credit, 7, false ]
  }.freeze

  def company(name, status: :open, currency_rates: nil)
    entity = create(:entity, name: name)
    ActsAsTenant.with_tenant(entity) do
      create(:fiscal_year, entity: entity, year: 2026, start_date: Date.new(2026, 1, 1), end_date: DATE, status: status)
      create(:journal, code: "OD", journal_type: :misc, entity: entity)
      CHART.each { |code, (type, balance, klass, reconcilable)| create(:account, entity: entity, code: code, label_fr: "A#{code}", account_type: type, normal_balance: balance, account_class: klass, reconcilable: reconcilable) }
    end
    entity
  end

  # lines: [code, debit, credit] or [code, debit, credit, partner]
  def book(entity, date, *lines)
    ActsAsTenant.with_tenant(entity) do
      entry = create(:journal_entry, :draft, entity: entity, journal: Accounting::Journal.find_by!(code: "OD"), fiscal_year: Accounting::FiscalYear.first, entry_date: date)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      lines.each do |code, debit, credit, partner|
        create(:journal_entry_line, entity: entity, journal_entry: entry, account: Accounting::Account.find_by!(code: code), partner: partner, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
      end
      Accounting::PostJournalEntry.call!(entry: entry)
    end
  end

  # A partner of `entity` that stands for the company `counterpart`.
  def stand_in(entity, counterpart, name: counterpart.name)
    ActsAsTenant.with_tenant(entity) { create(:partner, entity: entity, name: name, partner_type: :both, intercompany_company_id: counterpart.id) }
  end

  # The parent P (100 %) and the subsidiary S (80 %), with a loan of P to S, a sale of S to P and the trade balance it left: everything agrees.
  def parent_and_subsidiary(payable_in_parent: "1000.00")
    parent = company("Parent SA")
    sub    = company("Sub SRL")
    in_p, in_s = stand_in(parent, sub), stand_in(sub, parent)
    book(parent, DATE - 300, [ "550000", 100_000, 0 ], [ "100000", 0, 100_000 ])
    book(parent, DATE - 200, [ "290000", 20_000, 0, in_p ], [ "550000", 0, 20_000 ])
    book(parent, DATE - 100, [ "610000", payable_in_parent, 0, in_p ], [ "440000", 0, payable_in_parent, in_p ])
    book(parent, DATE - 90, [ "550000", 5_000, 0 ], [ "700000", 0, 5_000 ])
    book(sub, DATE - 300, [ "550000", 30_000, 0 ], [ "100000", 0, 30_000 ])
    book(sub, DATE - 200, [ "550000", 20_000, 0 ], [ "170000", 0, 20_000, in_s ])
    book(sub, DATE - 100, [ "400000", 1_000, 0, in_s ], [ "700000", 0, 1_000, in_s ])
    book(sub, DATE - 80, [ "610000", 2_000, 0 ], [ "550000", 0, 2_000 ])
    [ parent, sub ]
  end

  def make_group(parent, name: "The group", members: {})
    group = ActsAsTenant.with_tenant(parent) { Consolidation::Group.create!(name: name, currency: "EUR") }
    add_member(group, parent, stake: 100)
    members.each { |entity, options| add_member(group, entity, **options) }
    group
  end

  def add_member(group, entity, stake:, method: "full", currency: "EUR", **attrs)
    ActsAsTenant.with_tenant(group.entity) do
      member = group.members.create!(member_entity: entity, method: method, currency: currency, **attrs)
      member.stakes.create!(percentage: stake, effective_on: Date.new(2020, 1, 1))
      member
    end
  end

  # An accountant's validation of a rule, with the parameters the application proposes unless others are given.
  def validate_rule(group, key, parameters: nil, **attrs)
    ActsAsTenant.with_tenant(group.entity) do
      group.rule_validations.create!({ rule_key: key, validated_by_name: "Jane Doe", validated_by_title: "Chartered accountant, Doe & Co", validated_on: Date.current,
                                       reference: "QUESTIONS.md F12 / letter of the accountant", parameters: parameters || Consolidation::Rules::DEFINITIONS.dig(key, :parameters) || {} }.merge(attrs))
    end
  end

  def new_run(group, date: DATE)
    ActsAsTenant.with_tenant(group.entity) { group.runs.create!(reporting_date: date, entity: group.entity) }
  end

  def compute(run) = ActsAsTenant.with_tenant(run.entity) { Consolidation::Compute.call(run.reload) }
end

RSpec.configure { |config| config.include ConsolidationHelpers, :consolidation }

require "rails_helper"

# F02 acceptance criterion 4: on a reference set of 200 labelled lines, at least 70 % are matched automatically and there is no false
# positive at confidence 100 (nor anywhere above the threshold: a wrong proposal is worse than none).
# The set is built here, deterministically: 40 partners with names that share no word, customer invoices, and 200 bank lines of
# the kinds a bank sends (structured communication, invoice number, IBAN, name written differently, grouped payment, partial
# payment, ambiguous, unknown, bank fees). Each line says what it must give.
RSpec.describe "Matching reference set (200 lines)" do
  include_context "with_open_fiscal_year"

  WORDS = %w[Amber Birch Cobalt Dahlia Ember Fjord Garnet Harbor Indigo Jasper Kestrel Lagoon Meadow Nectar Onyx Pebble Quartz Raven Saffron Thistle
             Umber Velvet Willow Xenon Yarrow Zephyr Alder Basalt Cedar Dune Elm Fern Gorse Heath Iris Juniper Kelp Larch Maple Nettle Oak Pine
             Quill Reed Sage Tansy Ulex Vetch Wren Yew Zinnia Acorn Briar Clover Drift Eddy Flint Grove Hazel Isle Knoll Lichen Moss Nook Orchard
             Prairie Quarry Ridge Slate Tundra Upland Valley Wold Yonder Zenith Atoll Bayou Canyon Delta Estuary Fen Glade Hollow Inlet Jetty
             Kopje Lode Mesa Narrows Oasis Plateau Quay Rapids Shoal Tarn Umbra Vale Weald Xeric Yard Zone Anvil Bellows Chisel Dowel Easel Forge Gimlet].freeze

  let(:rng) { Random.new(2026) }
  let(:names) { WORDS.shuffle(random: rng).each_slice(3).first(40).map { |a| a.join(" ").upcase } }
  let(:partners) do
    names.each_with_index.map { |name, i| create(:partner, name: name, iban: CodaBuilder.iban(format("0912%08d", i + 1))) }
  end
  let(:bank_account) { create(:bank_account) }
  let(:serial) { @serial = (@serial || 0) + 1 }
  let(:cases) { [] }

  def invoice(partner, amount)
    number = format("VT2026/%05d", (@invoice_counter = (@invoice_counter || 0) + 1))
    create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner, due_date: Date.current + @invoice_counter).tap do |i|
      i.update_columns(total_incl_vat: BigDecimal(amount.to_s), invoice_number: number)
    end
  end

  def amount = (@amount = (@amount || 100) + 13.37).round(2) # every amount of the set is different
  def structured(target) = Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(target.id))

  # [line attributes, expected]: expected is nil (no proposal), or { target:, score: } / { targets:, score: } for a group.
  def add(attrs, expected) = cases << [ create(:bank_transaction, bank_account: bank_account, **attrs), expected ]

  before do
    grouped = partners.first(15).each # these partners have the three invoices of a grouped payment and nothing else
    p = partners.drop(15).cycle
    60.times { target = invoice(p.next, amount); add({ amount: target.total_incl_vat, description: structured(target), counterparty_name: "WHATEVER" }, { target: target, score: 100 }) }
    30.times { target = invoice(p.next, amount); add({ amount: target.total_incl_vat, description: "PAIEMENT #{target.invoice_number} MERCI" }, { target: target, score: 95 }) }
    30.times { partner = p.next; target = invoice(partner, amount); add({ amount: target.total_incl_vat, counterparty_iban: partner.iban, description: "VIREMENT" }, { target: target, score: 90 }) }
    20.times do
      partner = p.next
      target = invoice(partner, amount)
      name = [ partner.name.downcase, "#{partner.name} BVBA", partner.name.tr("AEIOU", "aeiou") ].sample(random: rng)
      add({ amount: target.total_incl_vat, counterparty_name: name, description: "PAIEMENT" }, { target: target, score: 75 })
    end
    15.times do
      partner = grouped.next
      group = [ invoice(partner, 1000 + amount), invoice(partner, 2000 + amount), invoice(partner, 4000 + amount) ]
      add({ amount: group.sum(&:total_incl_vat), counterparty_iban: partner.iban, description: "SOLDE" }, { targets: group, score: 80 })
    end
    10.times { target = invoice(p.next, 500 + amount); add({ amount: (target.total_incl_vat / 2).round(2), description: structured(target) }, { target: target, score: 80 }) }
    10.times do
      partner = p.next
      same = amount
      invoice(partner, same)
      invoice(partner, same)
      add({ amount: same, counterparty_iban: partner.iban, description: "VIREMENT" }, nil)
    end
    15.times { add({ amount: 7000 + amount, description: "REF #{rng.rand(10**8)}", counterparty_name: "NOBODY #{rng.rand(10**4)}" }, nil) }
    fees = create(:account, code: "651100", label_fr: "Frais bancaires")
    Accounting::BankRule.create!(name: "Bank fees", condition_type: "contains", condition_value: "frais de tenue de compte", account: fees, score: 85)
    10.times { add({ amount: -(1 + amount / 100).round(2), description: "FRAIS DE TENUE DE COMPTE #{rng.rand(100)}" }, { rule: true, score: 85 }) }
  end

  def verdict(transaction)
    suggestion = Accounting::MatchBankTransaction.call(transaction: transaction)
    suggestion && suggestion.score >= Banking::AutoMatch::MIN_SCORE ? suggestion : nil
  end

  def correct?(suggestion, expected)
    return suggestion.nil? if expected.nil?
    return false if suggestion.nil? || suggestion.score != expected[:score]
    return suggestion.kind == :rule if expected[:rule]
    return suggestion.target.map(&:id).sort == expected[:targets].map(&:id).sort if expected[:targets]

    suggestion.target == expected[:target]
  end

  # One example, one build of the set (it is the slow part): every claim of the criterion is checked on the same run.
  it "holds 200 lines, matches at least 70 % of them automatically to the right invoice with the right score, with no false positive at confidence 100 and no wrong proposal above the threshold", :aggregate_failures do
    outcomes = cases.map { |transaction, expected| [ transaction, expected, verdict(transaction) ] }
    matched = outcomes.count { |_, expected, suggestion| expected && correct?(suggestion, expected) }
    wrong = outcomes.reject { |_, expected, suggestion| correct?(suggestion, expected) }
    false_positives = outcomes.select { |_, expected, suggestion| suggestion&.score == 100 && !correct?(suggestion, expected) }

    expect(cases.size).to eq(200)
    expect(matched).to be >= 140                                  # 70 % of 200
    expect(matched).to eq(175)                                    # 60 + 30 + 30 + 20 + 15 + 10 partial + 10 rule: nothing is lost on this set
    expect(false_positives).to be_empty
    expect(wrong.map { |transaction, expected, _| [ transaction.description, transaction.amount.to_s, expected&.keys ] }).to be_empty
  end
end

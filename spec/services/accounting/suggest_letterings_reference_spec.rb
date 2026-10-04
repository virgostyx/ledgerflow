require "rails_helper"

# F04 §7 criterion 3: on a labelled reference set, the suggestions of score 100 are all right (no false positive) and cover the exact
# pairs. The set is built here, deterministically (no accountant's file was provided): 4 partners, 24 invoices each paid by a payment
# that carries its reference, plus decoys that look alike (same partner, same amount) and ambiguous references that must NOT reach 100.
RSpec.describe "Lettering suggestions on a reference set" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:journal)  { create(:journal, :cash) }
  let(:partners) { create_list(:partner, 4, :supplier) }

  def line(debit: 0, credit: 0, partner:, reference: nil, communication: nil, day: 10)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + day,
                                     **(reference ? { reference: reference } : {}))
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:bank_transaction, journal_entry: entry, structured_communication: communication) if communication
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  it "proposes 100 only for true pairs, and finds all the exact ones", :aggregate_failures do
    truth = {} # invoice line id => payment line id
    decoy_ids = []
    ambiguous_ids = []

    partners.each_with_index do |partner, p|
      6.times do |i|
        number = "FAC-#{p}#{i}-2026"
        amount = 100 + (i * 25) # the same six amounts for every partner, and the decoys repeat them
        invoice = line(credit: amount, partner: partner, reference: number, day: 10 + i)
        payment = line(debit: amount, partner: partner, communication: number.downcase.tr("-", " "), day: 40 + i)
        truth[invoice.id] = payment.id
      end
      # same partner, same amounts, no reference: could be mistaken for the pairs above, never certain
      decoy_ids += [ line(credit: 100, partner: partner, day: 80), line(debit: 100, partner: partner, day: 81) ].map(&:id)
      # two payments quoting the same reference of one invoice: ambiguous
      invoice = line(credit: 333, partner: partner, reference: "AMB-#{p}-2026", day: 90)
      twins = 2.times.map { line(debit: 333, partner: partner, communication: "amb #{p} 2026", day: 91) }
      ambiguous_ids += [ invoice.id, *twins.map(&:id) ]
    end

    Accounting::SuggestLetterings.call

    certain = Accounting::LetteringSuggestion.proposed.where(score: 100).to_a
    pairs   = certain.map { |s| s.line_ids.sort }
    expected = truth.map { |inv, pay| [ inv, pay ].sort }

    expect(certain.size).to eq(expected.size)
    expect(pairs).to match_array(expected) # every 100 is right, and every exact pair is there
    expect(certain.flat_map(&:line_ids) & (decoy_ids + ambiguous_ids)).to be_empty
  end
end

# Regenerates the CODA fixtures of F02 (fictitious data): `bin/rails runner spec/fixtures/files/coda/generate.rb`.
# They follow the Febelfin specification as built by spec/support/coda_builder.rb; they are not real bank files.
require Rails.root.join("spec/support/coda_builder")

B = CodaBuilder
DIR = Rails.root.join("spec/fixtures/files/coda")
ACME = B.iban("539007547034")
SAVINGS = B.iban("310123456789")

def write(name, text) = File.binwrite(DIR.join(name), text)
def d(day, month = 3) = Date.new(2026, month, day)

main = {
  iban: ACME, holder: "ACME SRL", sequence: 12, date: d(31), old_balance: "1000.00",
  movements: [
    { amount: "1210.00", value_date: d(2), bank_reference: "BKREF0000000000000001", structured: B.structured(1), counterparty_name: "DUPONT ET FILS SPRL",
      counterparty_iban: B.iban("091012345678"), counterparty_bic: "GKCCBEBB", customer_reference: "VIREMENT FACTURE 1" },
    { amount: "-605.00", value_date: d(5), bank_reference: "BKREF0000000000000002", free: "FACTURE F-2026-0042 BUREAU PLUS", counterparty_name: "BUREAU PLUS SA",
      counterparty_iban: B.iban("737000012345") },
    { amount: "-12.50", value_date: d(9), bank_reference: "BKREF0000000000000003", free: "FRAIS DE TENUE DE COMPTE", code: "41010000" },
    { amount: "250.00", value_date: d(15), bank_reference: "BKREF0000000000000004", structured: B.structured(2), counterparty_name: "MARTIN JEAN",
      counterparty_iban: B.iban("001234567890") }
  ]
}

# one account, four movements: two credits with structured communications, a payment with an invoice number, a bank fee
write("simple.cod", B.file(statements: [ main ]))

# two accounts in one file, each its own statement
write("two_accounts.cod", B.file(statements: [
  main,
  { iban: SAVINGS, holder: "ACME SRL", description: "COMPTE EPARGNE", sequence: 3, date: d(31), old_balance: "5000.00",
    movements: [ { amount: "-1000.00", value_date: d(10), free: "VIREMENT VERS COMPTE COURANT", counterparty_name: "ACME SRL", counterparty_iban: ACME } ] }
]))

# names with accents, in the two encodings banks use
accents = { iban: ACME, sequence: 13, date: d(31), old_balance: "0.00",
            movements: [ { amount: "99.99", value_date: d(3), free: "REMBOURSEMENT FRAIS DEPLACEMENT", counterparty_name: "JOSE GARCIA-LOPEZ", counterparty_text: "ÉCOLE DES BEAUX-ARTS ÇA ÜBER" } ] }
write("accents_latin1.cod", B.file(statements: [ accents ], holder_name: "SOCIÉTÉ ACME", encoding: "ISO-8859-1"))
write("accents_cp850.cod", B.file(statements: [ accents ], holder_name: "SOCIÉTÉ ACME", encoding: "CP850"))

# a movement with every sub-record: 2.1, 2.2, 2.3, 3.1, 3.2 and a free message (4)
write("detailed_movement.cod", B.file(statements: [
  { iban: ACME, sequence: 14, date: d(31), old_balance: "0.00",
    movements: [ { amount: "300.00", value_date: d(4), structured: B.structured(3), customer_reference: "CLIENT-REF-77", counterparty_bic: "KREDBEBB",
                   counterparty_name: "GLOBAL TRADING NV", counterparty_iban: B.iban("733012345678"), information: [ "DETAIL 1 ORDRE PERMANENT", "DETAIL 2 SUITE" ],
                   message: "MESSAGE LIBRE DE LA BANQUE" } ] }
]))

# statements that follow each other: the second opens on the balance the first closed on (a), or not (b)
write("chain_a.cod", B.file(statements: [ { iban: ACME, sequence: 20, date: d(15), old_balance: "100.00",
                                            movements: [ { amount: "50.00", value_date: d(10), bank_reference: "CHAIN0000000000000001", free: "A" } ] } ]))
write("chain_b_continues.cod", B.file(statements: [ { iban: ACME, sequence: 21, date: d(31), old_balance: "150.00",
                                                       movements: [ { amount: "-20.00", value_date: d(20), bank_reference: "CHAIN0000000000000002", free: "B" } ] } ]))
write("chain_b_break.cod", B.file(statements: [ { iban: ACME, sequence: 21, date: d(31), old_balance: "999.00",
                                                   movements: [ { amount: "-20.00", value_date: d(20), bank_reference: "CHAIN0000000000000002", free: "B" } ] } ]))

# two statements that overlap: the 10th and the 12th are in both
overlap_a = [ { amount: "10.00", value_date: d(10), bank_reference: "OVL000000000000000001", free: "UN", counterparty_name: "X" },
              { amount: "20.00", value_date: d(12), bank_reference: "OVL000000000000000002", free: "DEUX", counterparty_name: "Y" } ]
overlap_b = overlap_a + [ { amount: "30.00", value_date: d(14), bank_reference: "OVL000000000000000003", free: "TROIS", counterparty_name: "Z" } ]
write("overlap_a.cod", B.file(statements: [ { iban: ACME, sequence: 30, date: d(12), old_balance: "0.00", movements: overlap_a } ]))
write("overlap_b.cod", B.file(statements: [ { iban: ACME, sequence: 31, date: d(14), old_balance: "0.00", movements: overlap_b } ]))

# the new balance does not equal the old balance plus the movements
write("integrity_mismatch.cod", B.file(statements: [ main.merge(new_balance: "5555.55") ]))

# a structured communication whose check digits are wrong
write("invalid_structured.cod", B.file(statements: [
  { iban: ACME, sequence: 40, date: d(31), old_balance: "0.00",
    movements: [ { amount: "10.00", value_date: d(3), structured: B.structured(9, valid: false), counterparty_name: "X" } ] }
]))

# a foreign currency account
write("usd_account.cod", B.file(statements: [
  { iban: B.iban("539000000001"), currency: "USD", sequence: 50, date: d(31), old_balance: "2000.00",
    movements: [ { amount: "-300.50", value_date: d(8), free: "WIRE TO SUPPLIER", counterparty_name: "ACME INC" } ] }
]))

# files that must be refused whole
good = B.file(statements: [ main ]).lines
write("broken_length.cod", good.each_with_index.map { |l, i| i == 3 ? l.sub("\r\n", "  \r\n") : l }.join) # one record 130 characters long
write("truncated.cod", B.file(statements: [ main ], trailer: false))
write("unknown_record.cod", good.each_with_index.map { |l, i| i == 2 ? "7#{l[1..]}" : l }.join)
write("not_coda.cod", "this is not a CODA file\r\njust text\r\n")
puts "#{Dir[DIR.join('*.cod')].size} CODA fixtures in #{DIR}"

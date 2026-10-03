# CODA fixtures (F02)

Fictitious files (invented banks, holders, counterparties and IBANs, valid check digits, no real account), built by
`spec/support/coda_builder.rb` and written by `generate.rb` (`bin/rails runner spec/fixtures/files/coda/generate.rb`).
`spec/support_checks/coda_fixtures_spec.rb` checks that each file is what it claims to be.

They follow the Febelfin CODA specification v2.8 (annex I, `docs/dev/features/standard-coda-fr_-2025.pdf`): the layout of every record was checked against it. They test the parser against that specification, **not**
against the habits of each bank (extra spaces, unusual transaction codes, optional records left out, odd encodings).
When real files are available, anonymise them, drop them here as `real_<bank>_<n>.cod` and add them to the parser specs.

| File | What it is for |
| --- | --- |
| `simple` | one account, four movements: two structured communications, one invoice number, one bank fee |
| `two_accounts` | two logical files (0…9), one per account, in one physical file |
| `accents_latin1`, `accents_cp850` | the same text in the two encodings banks use |
| `detailed_movement` | 2.1, 2.2 (with R-transaction, reason, purposes), 2.3, two 3.1, and two free messages (4) after the new balance |
| `empty_account` | an account without movement: records 0, 1 and 9 only |
| `chain_a`, `chain_b_continues`, `chain_b_break` | statements that chain, and one that does not |
| `overlap_a`, `overlap_b` | two statements sharing movements |
| `integrity_mismatch` | the new balance is not the old balance plus the movements |
| `invalid_structured` | a structured communication with wrong check digits |
| `usd_account` | a foreign currency account |
| `broken_length`, `truncated`, `unknown_record`, `not_coda` | files to refuse whole |

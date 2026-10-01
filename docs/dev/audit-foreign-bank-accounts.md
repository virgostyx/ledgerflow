# Audit: bank accounts opened abroad (manual payments and reconciliations)

Date: 2026-10-01. Method: code reading plus throwaway probe specs (deleted). No product change made.

## Evidence

| # | Probe | Result |
|---|-------|--------|
| P1 | Create a `USD` bank account | Rejected: `BankAccount#currency` only allows `EUR` |
| P2 | Create an account with a local number (non-IBAN) | Rejected: IBAN is mandatory and validated |
| P3 | Import a CAMT.053 entry in USD into an EUR account, then reconcile | Accepted. Transaction keeps `USD`, but the entry is booked `550002 / 440000` for **1000.00 EUR**: the USD amount is silently treated as EUR |
| P4 | Put a USD invoice (1000 USD, booked 900 EUR at 0.9) in a SEPA batch | Accepted. Batch line = `1000.0` (invoice currency amount), no currency check |
| P5 | Pay that invoice with 950 EUR from the EUR account, letter | Works: FX loss 50.00 booked on `651200`. But `InvoiceSettlement.amount_eur` reports **900.00**; the 950.00 really paid and the FX difference are not exposed (so not sent to BudgetFlow) |
| P6 | Execute the SEPA batch of a USD invoice | Succeeds; the payment entry debits `440000` by the foreign amount (1000.01) against a 900.01 EUR booked payable: wrong by the exchange difference, no FX adjustment |

Also confirmed by reading: no manual bank-transaction entry (only CAMT.053.001.02 import; FX details of the statement ignored); payments are SEPA pain.001 only and need a valid partner IBAN (`Partner#sepa_payable?`); no exchange-rate table (rate typed per document); no period-end revaluation of foreign-currency balances; `BankAccount#balance_from_transactions` sums `amount` regardless of currency.

## Findings, by severity

**Blocking**
- F1. A foreign account cannot be declared (EUR-only, IBAN-only).
- F2. No way to record a movement by hand (no statement file from a foreign bank).
- F3. A manual payment (SWIFT, local transfer) has no payment path other than lettering by hand from an imported/typed transaction.

**Data integrity (wrong books)**
- F4. A transaction whose currency differs from its account is booked as if it were EUR (P3).
- F5. Foreign-currency invoices can enter a SEPA batch and the batch is posted with the foreign amount (P4, P6).

**Reporting / traceability**
- F6. Cash really paid, value date and FX gain/loss are not reported in the settlement shown to BudgetFlow (P5).
- F7. Bank balance and reconciliation report mix currencies.

**Missing accounting features**
- F8. No exchange-rate table; no revaluation of foreign balances at closing.

## Recommendations (priority order)

1. **Guard now (small, safe)**: reject a CAMT entry whose currency differs from the account's, and refuse non-EUR invoices in SEPA batches. Stops F4 and F5.
2. **Foreign accounts**: allow any ISO currency and a non-IBAN account number (IBAN required only when `currency == EUR` and SEPA). Fixes F1, F7 (balance per account currency).
3. **Manual bank transaction entry** (date, value date, amount, currency, reference) feeding the existing reconciliation and lettering flow. Fixes F2, F3.
4. **Manual payment of an invoice** from a foreign account: one action recording amount in account currency, converts to EUR with the actual rate, books the FX difference through `PostFxAdjustment`. Fixes F3, F5, F6.
5. **Settlement report**: expose real amount paid, currency, value date and FX difference in `InvoiceSettlement` and the BudgetFlow `paid` event (F6).
6. **Later**: exchange-rate table and closing revaluation (F8); a foreign-bank statement format (MT940/CSV) if manual entry becomes tedious.

Decision needed: which of 1–6 to implement (1 to 4 recommended as a first batch).

## Status (2026-10-01)

Implemented and committed locally (not pushed): recommendations 1 to 4.
1. CAMT entries must match the account currency; SEPA batches refuse non-EUR invoices and non-EUR debtor accounts.
2. Bank accounts accept any ISO currency; outside EUR the `iban` column holds a local account number (IBAN check only for EUR).
3. "Record a movement manually" on the reconciliation page; `BankTransaction` currency must equal its account's, reference unique per account.
4. "Pay a supplier invoice" on a pending debit (`Accounting::PayInvoiceFromTransaction`): bank/440000 lines carry the foreign amount, the EUR amount actually debited is entered by the accountant, the rate difference goes through `PostFxAdjustment`.

5. `InvoiceSettlement` (hence the `paid`/`payment_confirmed` events) carries `fx_difference_eur`, counts the real EUR debited (not capped at the booked amount) and no longer counts the FX adjustment line as a payment. BudgetFlow is unchanged: it ignores the new field; its `payment_amount_eur` already takes `amount_eur`.

Still open: 6.

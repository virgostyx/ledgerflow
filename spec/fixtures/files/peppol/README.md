# Peppol BIS Billing 3.0 examples

Downloaded on 2026-10-04 from the official repository of OpenPeppol, folder `rules/examples/`, at commit
`261c458474e27d58a25be629cccac28883171c92` (https://github.com/OpenPEPPOL/peppol-bis-invoice-3). Not modified.

| File | What it shows |
|---|---|
| `base-example.xml` | invoice: lines (one negative), a document charge, VAT 25 % |
| `base-creditnote-correction.xml` | the same as a credit note (`CreditNote`, `CreditNoteLine`) |
| `base-negative-inv-correction.xml` | an invoice with negative amounts (a correction) |
| `sales-order-example.xml` | despite its name, an invoice (same content as the base example) |
| `Allowance-example.xml` | document allowance and charge, two VAT categories (S 25, E 0), prepaid amount, a tax currency (two TaxTotal) |
| `Vat-category-S.xml` | two standard rates (25 and 15), allowance and charge |
| `vat-category-E.xml`, `vat-category-Z.xml`, `vat-category-O.xml` | exempt, zero-rated, out of scope; in GBP, GBP and SEK; no VAT number on the O one |

`constructed-reverse-charge-AE.xml` is **not official**: the repository has no reverse-charge example, so this one was written for the specs from
the shape of the base example (one line, category AE, 0 %, Belgian supplier).

The upstream repository declares no licence in its tree or its README. These files are small public examples published for implementers; they
are kept here as test fixtures only. If that is a concern, remove this folder and the specs that read it (`invoice_mapper_spec`,
`invoice_checks_spec`, `process_message_examples_spec`).

# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
- **Internal accountant**: daily, long sessions. Posts entries, reconciles (lettering), files VAT, closes fiscal years, runs reports. Dense, data-heavy work.
- **Project manager**: follows project budgets and analytic accounts (link with BudgetFlow), approves expenses, reads reports.
- **External parties via the portal**: suppliers, clients, the external accountant or auditor. Restricted, scoped access, never sees accounting internals.
- **Multi-entity operators**: one person or firm handling several entities (e.g. "ECES test", PRODEM) through an entity switcher.

## Product Purpose
Belgian accounting application, built for a Belgian foundation running EU-funded international development projects. It replaces WinBooks, which was costly, monolithic and disconnected from project management in BudgetFlow. Success: accurate, auditable books and compliant filings with less manual work.

## Positioning
Belgian accounting (PCMN chart, Belgian VAT / Intervat, Peppol/UBL, BNB) combined with per-project analytic accounting and a native link to BudgetFlow, with strict accounting immutability and a full audit trail. A generic accounting package could not truthfully claim this combination.

## Operating Context
Rails 8 / Hotwire / Tailwind / ViewComponent web app, separate from BudgetFlow and connected to it by a JWT-secured REST API. Validated entries are never edited or deleted, only reversed. Amounts are exact decimals. LedgerFlow never stores a user's bank credentials and never initiates a payment; it produces a file the human authorises in their bank. Anything coming from an external party is untrusted.

## Capabilities and Constraints
- Ledger, journals, PCMN, VAT, aged balance, financial reports, SEPA payment files, signature, agent, external portal (see `docs/dev/LedgerFlow_ConceptNote_v2.md` and the specs under `docs/dev/`).
- Money is shown right-aligned, monospace, never ambiguous in sign.
- The portal reads only its own `portal_*` data and exposes opaque tokens.

## Brand Commitments
- All user-visible text is in English.
- The brand colour replaces indigo (pages are being migrated; recent commits show the pattern).
- Visual coherence with BudgetFlow: light UI, Inter, Tailwind, ViewComponent.

## Evidence on Hand
No testimonials, customer logos, benchmarks or pricing exist in the repo. Do not fabricate any.

## Product Principles
1. Accounting truth first: immutability, exactness and auditability outrank convenience.
2. Dense but scannable: built for long working sessions, not for first impressions.
3. Never surprise with money: no automatic posting beyond documented exceptions, and no payment initiated by the app.
4. One family with BudgetFlow: shared conventions, not a separate look.
5. Externals see the minimum: scoped, tokenised, untrusted by default.

## Accessibility & Inclusion
WCAG AA (contrast and keyboard operation) for the working UI.

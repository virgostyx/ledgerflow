# API entrante (tiers → LedgerFlow) — audit et contrat

Statut : audit fait (2026-09-29), contrat validé avec l'utilisateur, code non commencé.
Plan détaillé : `~/.claude/plans/je-voudrais-revenir-sur-hidden-stallman.md`.

## Décisions
1. Objet injecté : `Accounting::Invoice` (pas d'écritures libres pour l'instant).
2. Modification / suppression d'une pièce comptabilisée : extourne + nouvelle pièce, jamais de réécriture.
3. Auth : table `api_clients` avec scopes, gérée dans Settings.
4. Synchrone et idempotent (clé = client + `external_ref`). Pas de lots asynchrones pour l'instant.

## Existant constaté
- `Api::V1::BaseController` : JWT HS256 à secret partagé, tenant lu dans `entity_id` du payload (le payload décide du tenant : à remplacer par `api_clients`).
- `Api::V1::InvoicesController` : lecture seule (index, show par id interne).
- `Api::V1::JournalEntriesController#create` : écriture 2 lignes en dur, journal achat, pas d'idempotence.
- `accounting_invoices.external_ref` et `project_id` existent, sans index d'unicité.
- Partenaires : index unique partiel (`entity_id`, `vat_number`), utilisable pour rapprocher le tiers.

## Points d'appui pour la mise en œuvre
- Création : `Accounting::PostInvoice.call(invoice:)` (exige une facture `draft` avec lignes ; refuse si la période TVA est déclarée).
- Annulation : `Accounting::CancelInvoice.call(invoice:)` ; refus déjà codés (payée, note de crédit, lot de paiement, immobilisation).
- Période : `FiscalYear.open_years` ; une date hors exercice ouvert doit être refusée en 422/409.

## Décisions complémentaires (2026-09-29)
- Révision : l'`external_ref` est conservé ; l'ancienne pièce est extournée et la nouvelle porte un numéro de révision.
- Tiers : BudgetFlow envoie chaque nouveau tiers à sa création via `PUT /api/v1/partners/:external_ref` (upsert idempotent, rapprochement possible par n° de TVA). Une facture qui référence un tiers inconnu est refusée en 422 ; pas de création implicite.
- Comptes : BudgetFlow envoie directement le code de compte PCMN ; un code inconnu → 422 avec la ligne concernée.

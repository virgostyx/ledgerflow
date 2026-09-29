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

## Questions ouvertes (à trancher avant l'étape 4)
- Une facture révisée garde-t-elle le même `external_ref` (avec un n° de révision), ou l'ancienne est-elle renommée à l'extourne ? Contrainte : l'index unique doit rester valide.
- Création automatique du partenaire si le n° de TVA est inconnu, ou refus 422 ?
- Comptes de charge : l'appelant fournit un code de compte PCMN, ou une table de correspondance côté LedgerFlow ?

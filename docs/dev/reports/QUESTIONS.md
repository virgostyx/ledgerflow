# Questions ouvertes — Rapports comptables

Journal des règles douteuses ou manquantes rencontrées pendant l'implémentation (règle du §16.1 de `docs/dev/reports/spec.md`). Comportement le plus prudent appliqué à chaque fois ; à faire valider.

## Bullet limité aux specs `bullet_strict` (socle, 2026-09-27)

Activer `Bullet.raise = true` globalement en test fait échouer 41 specs préexistants (hors périmètre rapports : factures, lettrage, immobilisations, rappels de paiement, journaux de paramétrage) qui contiennent de vrais N+1. Les corriger un par un est un chantier séparé, sans rapport avec les rapports comptables.

**Décision appliquée** : Bullet reste actif en log seul pour toute la suite, et ne fait échouer que les specs explicitement taguées `bullet_strict: true` (voir `spec/support/bullet_strict.rb`) — appliqué pour l'instant aux specs de `app/queries/accounting/*_query.rb` et `spec/requests/accounting/reports_spec.rb`.

**À faire valider** : traiter les 41 N+1 existants dans un chantier dédié, puis retirer le tag `bullet_strict` au profit d'un `Bullet.raise = true` global.

Liste des specs actuellement en échec sous Bullet strict global (pour référence du futur chantier) : `bank_reconciliation_spec.rb`, `fixed_assets_spec.rb`, `invoices_spec.rb`, `journal_entries_spec.rb`, `opening_invoice_spec.rb`, `payment_batches_spec.rb`, `payment_reminders_spec.rb`, `recurring_invoices_spec.rb`, `settings/journals_spec.rb`, `journal_entry_workflow_spec.rb` (system), `lettering_workflow_spec.rb` (system).

## `reconciliation_items` non créée : réutilisation de `accounting_line_allocations` (socle, 2026-09-27)

Le §7 de la spec demande une table `reconciliation_items(line_id, reconciliation_id, amount)` pour recalculer `amount_residual` à une date passée. Le dépôt a déjà exactement cette information, sous une forme différente et plus riche : `accounting_line_allocations` (`debit_line_id`, `credit_line_id`, `amount`, `allocated_on`) pour les lettrages partiels, et `accounting_letterings.lettered_on` pour la date d'un lettrage total.

**Décision appliquée** : ne pas créer de table dupliquée. `amount_residual` (ajoutée sur `accounting_journal_entry_lines`) est maintenue par les services de lettrage/allocation eux-mêmes (`Accounting::JournalEntryLine.resync_amount_residual!`, appelée dans `CreateAllocations`, `CreateLettering`, `UnletterLines`, `RemoveAllocation` — ces écritures passent par `update_all`/`nullify`/`destroy_all`, qui contournent les callbacks ActiveRecord, d'où l'appel explicite à chaque endpoint plutôt qu'un callback modèle unique).

**À faire valider en implémentant R04** : la reconstruction rétroactive (`as_of` dans le passé, critère d'acceptation R04 #2) devra filtrer `accounting_line_allocations.allocated_on <= as_of` et `accounting_letterings.lettered_on <= as_of` — `AgedBalanceQuery` actuelle ne le fait pas encore (elle utilise l'état courant, pas un état reconstruit à une date passée). C'est un vrai écart à corriger dans le chantier R04, pas dans le socle.

## `Reports::Exporters::Pdf` via Prawn, pas Ferrum (socle, 2026-09-27)

Le §14 de la spec décrit le PDF comme "rendu HTML → PDF via Ferrum, qui réutilise le CSS d'impression des vues", HexaPDF en alternative. Ni l'un ni l'autre n'est câblé dans ce dépôt (Ferrum est au Gemfile mais utilisé seulement pour les tests système ; HexaPDF est absent). `Accounting::InvoicePdf` existe déjà et génère des PDF via Prawn + prawn-table.

**Décision appliquée** : `Reports::Exporters::Pdf` réutilise Prawn/prawn-table, comme `InvoicePdf`, pour un tableau générique (titre, en-tête en gras, pagination "x / y"). Pas de vue HTML à réutiliser pour un exporteur générique de toute façon — la question du rendu HTML→PDF via Ferrum ne se posera vraiment que si un rapport a besoin d'une mise en page plus riche qu'un tableau (graphiques du §17, par exemple).

**À faire valider** : si un futur rapport a besoin d'un rendu plus riche que Prawn ne permet pas facilement (mise en page complexe, graphiques intégrés au PDF), reconsidérer Ferrum à ce moment-là plutôt que maintenant.

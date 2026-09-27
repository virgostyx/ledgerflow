# Questions ouvertes — Rapports comptables

Journal des règles douteuses ou manquantes rencontrées pendant l'implémentation (règle du §16.1 de `docs/dev/reports/spec.md`). Comportement le plus prudent appliqué à chaque fois ; à faire valider.

## Bullet limité aux specs `bullet_strict` (socle, 2026-09-27)

Activer `Bullet.raise = true` globalement en test fait échouer 41 specs préexistants (hors périmètre rapports : factures, lettrage, immobilisations, rappels de paiement, journaux de paramétrage) qui contiennent de vrais N+1. Les corriger un par un est un chantier séparé, sans rapport avec les rapports comptables.

**Décision appliquée** : Bullet reste actif en log seul pour toute la suite, et ne fait échouer que les specs explicitement taguées `bullet_strict: true` (voir `spec/support/bullet_strict.rb`) — appliqué pour l'instant aux specs de `app/queries/accounting/*_query.rb` et `spec/requests/accounting/reports_spec.rb`.

**À faire valider** : traiter les 41 N+1 existants dans un chantier dédié, puis retirer le tag `bullet_strict` au profit d'un `Bullet.raise = true` global.

Liste des specs actuellement en échec sous Bullet strict global (pour référence du futur chantier) : `bank_reconciliation_spec.rb`, `fixed_assets_spec.rb`, `invoices_spec.rb`, `journal_entries_spec.rb`, `opening_invoice_spec.rb`, `payment_batches_spec.rb`, `payment_reminders_spec.rb`, `recurring_invoices_spec.rb`, `settings/journals_spec.rb`, `journal_entry_workflow_spec.rb` (system), `lettering_workflow_spec.rb` (system).

# Questions ouvertes — Fonctions transverses (F01 à F13)

Décisions prises par prudence pendant l'implémentation (règle du §17.1 de `docs/dev/features/spec.md`), à faire valider.

## F01 — Rôles
- **Correspondance des rôles** : le code a `admin`, `accountant`, `manager`, `auditor` ; la spec a Propriétaire, Comptable, Assistant, Lecteur, Auditeur externe. Décision : garder les 4 rôles actuels sans rien changer de leurs droits, et ne pas ajouter « Assistant » ni « Auditeur externe » tant qu'on n'a pas tranché qui fait quoi. **À valider** : `manager` devient-il l'Assistant (saisie de brouillons, lettrage, export) ? `auditor` voit-il les rapports (la spec dit oui, le code dit non) ?
- **`users.role` global** : conservé en base (utilisé par les seeds, l'API héritée) mais **plus lu par aucune policy**. À supprimer ou à réduire à « administrateur de la plateforme » quand ce rôle existera.

## F01 — Quatre yeux
- Appliqué aux seules écritures **saisies à la main** (`created_by_id`). Les écritures générées par une facture, un paiement, la clôture ou un import n'ont pas d'auteur et ne sont pas bloquées, sinon chaque postage de facture serait refusé à l'auteur de la facture. **À valider** : faut-il un contrôle équivalent sur la validation d'une facture (auteur du brouillon ≠ valideur) ?
- Seuil : la règle s'applique à partir du total au débit, borne incluse.

## F01 — Verrouillage
- Le **lettrage reste possible** dans une période verrouillée (spec F04), y compris au niveau du trigger. Le délettrage d'une ligne d'une période verrouillée devrait exiger `reconciliations.unreconcile_locked` (F04) : pas encore le cas.
- **Verrou TVA** : la spec veut que la déclaration TVA utilise `period_locks`. Aujourd'hui `VatDeclaration` a son propre statut. À relier avec R09.
- **Extourne d'une écriture d'une période verrouillée** : `ReverseJournalEntry` date l'extourne à la même date et sera donc refusée ; la règle de la spec (premier jour de la première période ouverte) est prévue dans F07.

## Drapeaux
- Colonne jsonb `entities.features` plutôt que Flipper (décision validée). Éteint par défaut ; le propriétaire active. L'« administrateur de la plateforme » de la spec n'existe pas comme rôle : aujourd'hui, seul le propriétaire de la société active un drapeau.

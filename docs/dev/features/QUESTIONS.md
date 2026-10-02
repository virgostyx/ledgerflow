# Questions ouvertes — Fonctions transverses (F01 à F13)

Décisions prises par prudence pendant l'implémentation (règle du §17.1 de `docs/dev/features/spec.md`), à faire valider.

## F01 — Rôles
- **Correspondance retenue (décision de l'utilisateur)** : `admin` = Propriétaire, `accountant` = Comptable, `assistant` (nouveau) = Assistant, `manager` = Lecteur, `auditor` = Auditeur externe. Les noms stockés ne changent pas, seuls les libellés. Conséquences assumées : l'auditeur externe voit désormais les rapports (la spec le veut) ; le Lecteur perd la piste d'audit, la liasse et les contrôles de cohérence (réservés à propriétaire, comptable et auditeur externe).
- **`users.role` global** : conservé en base (seeds, API héritée) mais **plus lu par aucune policy**. À supprimer ou à réduire à « administrateur de la plateforme » quand ce rôle existera.
- **Assistant et rapprochement** : la spec lui permet de rapprocher, ce qui valide aujourd'hui le paiement. À corriger par F02 (brouillon par défaut), sinon l'assistant valide indirectement.
- **Export des rôles en lecture** : une seule option de société (`read_only_export`), éteinte par défaut, pour Lecteur et Auditeur externe ensemble (décision de l'utilisateur).

## F01 — Quatre yeux
- Appliqué aux seules écritures **saisies à la main** (`created_by_id`). Les écritures générées par une facture, un paiement, la clôture ou un import n'ont pas d'auteur et ne sont pas bloquées, sinon chaque postage de facture serait refusé à l'auteur de la facture. **À valider** : faut-il un contrôle équivalent sur la validation d'une facture (auteur du brouillon ≠ valideur) ?
- Seuil : la règle s'applique à partir du total au débit, borne incluse.

## F01 — Verrouillage
- Le **lettrage reste possible** dans une période verrouillée (spec F04), y compris au niveau du trigger. Le délettrage d'une ligne d'une période verrouillée devrait exiger `reconciliations.unreconcile_locked` (F04) : pas encore le cas.
- **Verrou TVA** : la spec veut que la déclaration TVA utilise `period_locks`. Aujourd'hui `VatDeclaration` a son propre statut. À relier avec R09.
- **Extourne d'une écriture d'une période verrouillée** : `ReverseJournalEntry` date l'extourne à la même date et sera donc refusée ; la règle de la spec (premier jour de la première période ouverte) est prévue dans F07.

## Drapeaux
- Colonne jsonb `entities.features` plutôt que Flipper (décision validée). Éteint par défaut ; le propriétaire active. L'« administrateur de la plateforme » de la spec n'existe pas comme rôle : aujourd'hui, seul le propriétaire de la société active un drapeau.

## F01 — Second facteur et clés d'API
- **QR code** : gem `rqrcode` ajoutée (décision de l'utilisateur) ; le code TOTP lui-même est écrit sans gem (RFC 6238).
- **Chiffrement** : `users.totp_secret` utilise `encrypts` : en production, les clés `active_record_encryption` doivent exister (`bin/rails db:encryption:init`), comme pour les identifiants Peppol.
- **Perte de l'application d'authentification** : pas de procédure en libre-service. À décider : codes de secours TOTP, ou réinitialisation par un propriétaire (écran).
- **Clés d'API sans propriétaire** (émises avant F01) : elles gardent leur comportement jusqu'à la prochaine rotation. À décider : les migrer en attribuant un propriétaire, ou refuser les clés sans propriétaire après une date.
- **Défaut `post` de l'API** : l'API valide si `post` est absent. Un propriétaire sans droit de valider reçoit 403 plutôt qu'un brouillon silencieux (choix prudent : l'intégration saurait sinon moins ce qui s'est passé).

## F03 — Documents
- **Durée de conservation** : 10 ans à partir du dépôt, pour tous les types (la spec dit « calculé par type, défaut 10 ans, à confirmer avec la réglementation »). **À valider par un comptable** : durée, point de départ (dépôt ou clôture de l'exercice de l'écriture liée) et durée par type.
- **Aucune suppression avant le terme**, même d'un document déposé par erreur : on l'archive. Strict, conformément à la spec ; à confirmer si une correction de dépôt (suppression dans les N minutes, tant que rien n'est lié) est souhaitée.
- **Type CSV** : accepté si le nom finit par `.csv` et que le contenu est du texte. **Texte brut** (`.txt`) refusé.
- **XML avec `<!DOCTYPE`** : refusé en bloc plutôt que nettoyé. Un UBL BIS 3.0 n'en contient pas.
- **Service de fichiers par l'application** plutôt que par des adresses signées d'Active Storage : plus simple à rendre étanche par société et par droit. Les « liens signés à durée limitée » dont parle la spec (réponse d'un tiers, F08) restent à construire.
- **Chiffrement au repos / S3 / sauvegarde** : le volume `ledgerflow_storage` doit être sauvegardé et chiffré par l'hébergement ; rien dans le code ne chiffre les fichiers.
- **Dépendances système** pour l'extraction à venir : `tesseract-ocr` (avec les langues fr, nl, en) et `poppler-utils` (`pdftotext`, `pdftoppm`) dans l'image Docker.


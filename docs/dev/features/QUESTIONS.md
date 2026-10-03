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
- **Extraction : propositions seulement.** Rien lu d'un document n'est appliqué sans confirmation. Le brouillon de facture utilise la valeur confirmée, à défaut la valeur proposée (l'audit liste les champs qui n'étaient que proposés). **À valider** : faut-il exiger que les champs essentiels (numéro, date, total) soient confirmés avant de créer le brouillon ?
- **Brouillon sans ligne.** Le brouillon ne reçoit aucune ligne (pas de compte deviné, pas de TVA devinée) ; seuls les montants de référence de l'en-tête sont préremplis. Les factures saisies dans l'interface ne bloquent pas une ligne sur un compte d'attente à la validation (seules les factures de l'API le font), d'où ce choix.
- **Doublon probable** : même fournisseur + même numéro de facture, hors factures annulées. La spec cite aussi « même montant » : non exigé ici (un numéro réutilisé avec un autre montant reste un doublon à examiner). Contournable avec un motif, audité.
- **OCR** : seuil de confiance de 60 (moyenne des mots) en dessous duquel rien n'est gardé ; langues fra, nld, eng quand elles sont installées. Seuil et langues à régler à l'usage sur de vrais scans.
- **Devise du brouillon** : EUR, ou la devise lue si son taux est connu dans la table des taux de la société ; jamais de taux deviné.
- **Résultats de lecture sur un document figé** : écrits (données dérivées) même si le document est lié à une écriture validée ; le fichier et ses détails restent figés, la confirmation d'un champ est refusée.
- **Recherche** : trigramme sur `search_blob` plutôt que `tsvector` (écart à la spec §6) ; suffisant pour noms, numéros et montants.
- **Rétention par nature** : `RETENTION_YEARS_BY_KIND` (défaut 10 ans) ; une nature plus longue prolonge, jamais ne raccourcit. **À valider par un comptable.**
- **Suspension légale** : motif obligatoire, réservée au propriétaire ; un document suspendu ne peut pas être supprimé même après son terme.
- **Antivirus** : fermé par défaut dès qu'un scanner est configuré (panne = refus). Choisir le scanner (ClamAV ?) et `FAIL_OPEN` selon l'hébergement.
- **ZIP** : limites 50 fichiers / 100 Mo / ratio 100, à ajuster à l'usage.
- **Adresse e-mail** : le jeton fait l'authentification ; quiconque le connaît peut déposer des documents (jamais lire). Domaine et relais à configurer par l'hébergement ; pas de réponse à l'expéditeur (ni accusé ni refus) pour ne rien révéler.
- **Dépendances système** de production : `tesseract-ocr` (+fra, nld), `poppler-utils`, `ghostscript`, `imagemagick` ; clés `active_record_encryption` (secret TOTP, identifiants Peppol).
- **Assistant et rapprochement bancaire (F01)** : la spec le laisse rapprocher mais pas valider ; comptabiliser un mouvement valide l'écriture de paiement. Résolu avec F02 : l'assistant produit des brouillons (ligne « matched », écriture à valider) ; seul le paiement d'une facture fournisseur lui reste refusé. **À valider** : faut-il aussi lui ouvrir le paiement fournisseur en brouillon (lettré à la validation) ?
- **Report à nouveau sur un exercice non clôturé (F01)** : l'écriture d'ouverture ne reprend que les comptes de bilan ; si les comptes de résultat n'ont pas été soldés par la clôture, elle est déséquilibrée et désormais refusée (message « Unbalanced entry »). Clôturer l'exercice d'abord. Reporter le résultat non soldé sur 130000 reste une règle à faire valider.
- **JWT historique de BudgetFlow (F01)** : fermé par défaut (`LEGACY_JWT_ENABLED=1` pour l'ouvrir), limité aux routes à portée déclarée, journalisé dans l'audit. `journal_entries` et `projects/accounting_summary` ont reçu la portée `invoices:read` pour rester joignables par des clés bornées. **À décider** : date de suppression du JWT, après migration de BudgetFlow vers des clés `lf_…` (aucune modification de BudgetFlow sans accord).
- **Période TVA déposée = période verrouillée (F01)** : conformément à la spec (§4 et R09), le dépôt verrouille toute la période pour toute écriture. **À valider** : un paiement ou un rapprochement bancaire daté dans une période déjà déposée est donc refusé (il faut le dater dans la période suivante ou faire déverrouiller par un propriétaire). Les déclarations déposées avant ce changement ne sont pas verrouillées (aucune donnée modifiée).
- **Restriction par journal (F01)** : la spec ne précise pas ce qu'elle limite. Retenu : saisie, lecture, validation et extourne des écritures et factures d'un journal. Les rapports agrégés ne sont pas filtrés (le grand livre et la balance montrent tous les comptes). **À valider** : faut-il filtrer aussi les rapports et le drill-down par journal ? C'est un chantier plus large (chaque requête de rapport).
- **Rôles personnalisés (F01)** : `users.manage` interdit dans un rôle personnalisé (sinon un non-propriétaire pourrait nommer des propriétaires). **À valider** : faut-il aussi réserver aux propriétaires `periods.unlock`, `fiscal_years.manage` et `documents.delete_expired` ? Ils sont aujourd'hui composables : un propriétaire peut les donner à un rôle personnalisé, avec second facteur exigé pour `periods.unlock`.

## F02 — Import CODA et rapprochement
- **Fichiers CODA fictifs, pas de vrais.** Le parseur suit la norme Febelfin v2.8 (annexe I relue enregistrement par enregistrement) et est testé sur des fichiers fabriqués conformes. Les habitudes propres à chaque banque (espaces en trop, codes d'opération inhabituels, enregistrements facultatifs absents, jeux de caractères) ne sont pas vérifiées. **À faire** : déposer de vrais fichiers anonymisés de deux ou trois banques dans `spec/fixtures/files/coda/` (`real_<banque>_<n>.cod`) et les ajouter aux specs du parseur.
- **Détection de l'encodage** : UTF-8 s'il l'est, CP850 si un octet 0x80–0x9F apparaît, sinon ISO-8859-1. Un fichier CP850 qui ne contiendrait que des lettres accentuées au-dessus de 0xA0 serait lu en ISO-8859-1. L'appelant peut imposer l'encodage ; aucun écran ne le propose encore.
- **Un écart de chiffre d'affaires dans l'enregistrement 9** (montants totaux) n'est qu'un avertissement ; le nombre d'enregistrements faux refuse le fichier. À confirmer.
- **Globalisation** : les mouvements de détail (même séquence, détail > 0) ne sont pas importés comme lignes, seul le total l'est (le détail reste dans `raw_data`). Pour rapprocher un lot de recouvrements ligne à ligne, il faudra décider ce qu'on importe.
- **Tolérance d'arrondi** : tranchée avec vous : deux comptes dédiés 658100 (charge) et 758100 (produit), créés par le propriétaire sur une société existante (jamais en silence) ; recettes seulement. **À valider par un comptable** : ces numéros de compte.
- **Virements entre deux comptes de la société** : faits, via le compte 580000 (virements internes) déjà utilisé pour les retraits de caisse ; appariement par IBAN, 3 jours, unicité. **À valider** : la fenêtre de 3 jours et l'exigence d'un IBAN.
- **Paiements fournisseurs** : en brouillon sur confirmation (jamais automatique), facture entière en euros ; lettrés à la validation. Acompte et devise : écriture validée seulement.
- **Règle de société « Book a draft »** : le brouillon est créé dès l'import, sans confirmation, même sous 100. C'est le sens de la règle ; à confirmer avec un comptable pour les montants importants.
- **TVA d'une règle** : non appliquée, par prudence (pas de pièce de TVA derrière une ligne de banque) ; colonne retirée.
- **R06** : avec des relevés, le solde du relevé est le solde de clôture du dernier ; seul ce qui suit le solde d'ouverture du plus ancien relevé est comparé ligne à ligne. Un grand livre qui s'ouvre autrement que la banque se voit comme écart. Sans relevé (CAMT, CSV, saisie), R06 garde son calcul plat.
- **Rupture de chaînage** : calculée avec le relevé précédent connu à l'import ; pas recalculée quand un relevé intermédiaire arrive plus tard.
- **Jeu de référence de 200 lignes** : construit dans le spec, pas fourni par un cabinet. Le taux de 87,5 % ne dit rien du taux sur de vrais dossiers.


## F04 — Lettrage assisté
- **« Même référence » (règles 1 et 2)** : une ligne porte, au plus, la référence de son écriture, le numéro et la référence fournisseur de sa facture, et la communication structurée du relevé bancaire qui l'a créée. Comparaison sans casse, sans ponctuation, 4 caractères au minimum. À valider avec un comptable : d'autres sources (libellé de ligne) ne sont pas lues.
- **Score 100 = jamais une devinette.** La règle 1 exige un paiement (facture contre note de crédit = règle 2) et refuse toute paire dont une ligne pourrait s'apparier à une autre : les cas ambigus tombent à 90. Le job nocturne n'appliquera que ces suggestions.
- **Lignes partiellement imputées** : exclues des suggestions (la spec dit « seul son résiduel est proposé », mais `LetterLines` refuse de lettrer une ligne partielle hors de son groupe d'imputation). Le résiduel se règle par l'imputation manuelle existante.
- **Règle 4** : lignes ouvertes d'un tiers sur un compte, au moins 3 (les paires sont déjà couvertes), somme nulle. **Règle 5** : recherche bornée à 8 lignes et aux 16 lignes de signe contraire les plus proches en date.
- **Règle 6 et écart d'arrondi** : accepter la suggestion (ou `WriteOffLettering`) crée une écriture de régularisation **en brouillon** dans le journal divers : crédit/débit du compte du tiers, contrepartie 658100 (charge, si Σ débit > Σ crédit) ou 758100 (produit). Lecture prudente de « les lignes de brouillon ne se lettrent pas » : le lettrage (nature `write_off`, avec la ligne de régularisation) n'est fait qu'à la validation du brouillon, par la même personne ; s'il échoue, la validation tient et les lignes restent ouvertes. Le seuil est `bank_rounding_tolerance` ; les deux comptes doivent exister ; l'écriture est datée comme la plus récente des lignes (une période verrouillée refusera sa validation). **À valider** : le seuil unique pour clients et fournisseurs, et l'usage de 758100 en achats. La nature `partial` n'est pas utilisée : l'imputation partielle reste `line_allocations`. Si le brouillon est supprimé, les lignes sont proposées de nouveau.
- **Suggestions en euros uniquement** : les montants sont ceux du grand livre ; le multi-devise relève de F11.
- **Lettrage automatique (`auto_reconcile_exact`)** : désactivé par défaut, case dans les paramètres de la société (propriétaire seulement). Le job de 1 h recalcule les suggestions puis lettre celles de score 100, sans utilisateur (`lettered_by` vide, `auto` vrai), avec une ligne d'audit `auto_lettering` (règle, score, lignes). Une suggestion qui ne tient plus est laissée telle quelle. **À valider** : l'heure du job et le fait qu'aucune notification n'est envoyée.

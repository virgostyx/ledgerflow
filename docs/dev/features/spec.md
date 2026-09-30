# Spécification des fonctions transverses – LedgerFlow

Sep 26, 2026 · @Virgo STYX

## 1. Contexte et périmètre

Ce document décrit 13 fonctions transverses de LedgerFlow, hors rapports, classées en quatre vagues (P0 à P3), avec pour chacune le modèle de données, les règles, l'interface, les cas limites, les critères d'acceptation et les tests. Il complète la spécification des rapports (`docs/reports/SPEC.md`), dont il reprend le gabarit, les invariants comptables et la définition de « terminé ».

Il est écrit pour être donné tel quel à un agent de codage (Claude Code). L'agent le lit en entier, audite le dépôt, puis implémente fonction par fonction (voir §17).

**Hypothèses de travail** (à corriger si elles sont fausses):

- Application Ruby on Rails avec PostgreSQL, ViewComponent, Stimulus, Tailwind, LightService et RSpec, développée en TDD.
- Cadre belge: PCMN, TVA belge, CODA pour les relevés bancaires, Peppol pour la facturation électronique, WinBooks comme logiciel d'origine à remplacer.
- Multi-sociétés: chaque donnée est bornée à la société courante.
- L'intégration Peppol via Digiteal et l'authentification JWT de l'API existent déjà, au moins en partie. L'agent les audite et les étend; il ne les réécrit pas.
- Les rapports de la spécification précédente sont implémentés ou en cours: plusieurs fonctions s'y branchent (R04, R05, R06, R18, R19).

**Gabarit de chaque fonction**: Objectif · Modèle de données · Règles · Interface · Cas limites · Sécurité · Critères d'acceptation · Tests.

**Hors périmètre**: comptabilité de paie, déclarations fiscales à l'impôt des sociétés, dépôt des comptes annuels, application mobile native.

## 2. Principes transverses

Ces règles s'appliquent à chaque fonction. Elles reprennent celles de la spécification des rapports (§2) et ajoutent celles qui concernent les fonctions qui écrivent des données.

### 2.1 Architecture

- Une fonction = un dossier `app/features/<nom>/` avec ses services LightService, ses composants ViewComponent, ses jobs et ses policies. Les modèles ActiveRecord restent dans `app/models/`.
- **Services d'écriture comptable**: toute création, validation ou extourne d'écriture passe par un service unique (`Ledger::PostEntry`, `Ledger::ReverseEntry`). Aucune fonction n'écrit directement dans `journal_entries` ni `journal_entry_lines`.
- **Idempotence**: tout import ou traitement de fond porte une clé d'idempotence (hash du contenu et de la société). Le relancer ne crée aucun doublon.
- **Jobs**: ActiveJob avec trois tentatives, attente croissante, statut visible dans l'interface et journal des erreurs.
- **API**: chaque fonction expose ses actions principales sous `/api/v1/` (JWT), avec les mêmes autorisations que l'interface.

### 2.2 Autorisation et sécurité

- Autorisation par action, via des policies (`Pundit` ou l'existant), toujours testées avec un exemple partagé.
- Aucune requête sans scope société. Les fichiers stockés (pièces, imports) sont accessibles par lien signé qui vérifie la société et le droit de l'utilisateur.
- Les fichiers reçus sont contrôlés: type MIME réel, taille maximale, analyse antivirus si disponible, jamais exécutés.
- Aucune donnée sensible dans les journaux applicatifs (IBAN complet, contenu de pièces); masquage systématique.

### 2.3 Audit

Chaque action qui crée, modifie, supprime, valide, importe, exporte ou change un droit est journalisée dans `audit_logs` (R18): acteur, action, objet, avant et après, motif si l'action touche une écriture validée. Une fonction qui n'écrit pas dans l'audit n'est pas terminée.

### 2.4 Règles comptables

- Montants en `numeric(15,2)`, `BigDecimal` en Ruby, jamais `Float`.
- Une écriture validée ne se modifie pas: on l'extourne. Les brouillons sont modifiables.
- Les invariants I1 à I11 de la spécification des rapports doivent rester verts après chaque fonction. Un test d'invariants tourne à la fin de chaque parcours système.
- Aucun traitement automatique ne valide une écriture sans règle explicite: par défaut, il crée un **brouillon** qu'un humain valide. Les exceptions sont listées fonction par fonction.

### 2.5 Interface et accessibilité

- Locales fr, nl et en, libellés dans `config/locales/features.*.yml`.
- Turbo et Stimulus pour l'interactivité; chaque action a un état de chargement, un état vide et un message d'erreur localisé.
- Toute action destructive ou irréversible demande une confirmation explicite qui rappelle ses effets.
- Navigation au clavier et attributs ARIA sur les tableaux, les listes de tâches et les fenêtres modales.

## 3. Feuille de route

Les fonctions suivent l'ordre ci-dessous. Une vague n'est terminée que lorsque tous ses critères d'acceptation passent et que les invariants I1 à I11 sont verts; l'agent ne démarre pas la vague suivante avant.

| Ordre | Réf. | Fonction | Vague | Dépend de | Effort |
| --- | --- | --- | --- | --- | --- |
| 1 | F01 | Droits par rôle et verrouillage de périodes | P0 | Audit (R18, journalisation) | L |
| 2 | F03 | Gestion documentaire des pièces | P0 | F01 | L |
| 3 | F02 | Import CODA et rapprochement bancaire automatique | P0 | F01, F03, R06 | XL |
| 4 | F04 | Lettrage assisté | P1 | F02, R05 | M |
| 5 | F05 | Migration depuis WinBooks | P1 | F01 | XL |
| 6 | F06 | Facturation électronique Peppol (audit et extension de l'existant) | P1 | F03 | L |
| 7 | F07 | Écritures récurrentes, modèles et extourne | P1 | F01, F04 | M |
| 8 | F08 | Tâches et commentaires par écriture ou par compte | P2 | F01 | M |
| 9 | F09 | Relances clients | P2 | R04, F08 | M |
| 10 | F11 | Multi-devises et écarts de change | P2 | F01, F04, F07 | L |
| 11 | F10 | Clôture d'exercice guidée | P2 | F01, F07, F11, R09, R16, R17, R19 | XL |
| 12 | F12 | Multi-dossiers et consolidation | P3 | F11 et les rapports | XL |
| 13 | F13 | Import, export et API | P3 | F01 | L |

Effort relatif avec un agent de codage: S = une session, M = deux à trois, L = quatre à six, XL = plus de six.

F03 passe avant F02 parce que le drill-down des rapports mène à la pièce et que l'import bancaire s'appuie sur les mêmes mécanismes de stockage et de fichiers signés. F05 (migration) peut être avancée en fin de P0 si un dossier réel doit être repris rapidement: elle fournit aussi les données de contrôle des rapports R07 à R09.

**Critères de sortie de chaque vague**

- **P0**: un utilisateur sans droit de validation ne peut pas valider; une période verrouillée refuse toute écriture; une pièce est consultable depuis une écriture; un relevé CODA importé deux fois ne crée aucun doublon et la majorité des lignes sont rapprochées automatiquement sur le jeu de référence.
- **P1**: le lettrage propose des paires exactes sur le jeu de référence; un dossier WinBooks de référence est importé et sa balance égale celle de WinBooks à l'euro près; une facture Peppol reçue crée un brouillon lié à sa pièce; une écriture récurrente se génère à date.
- **P2**: les tâches et les relances sont utilisables depuis R04 et R05; la clôture guidée mène de la liste de contrôles aux écritures de clôture sans étape manuelle cachée; une écriture en devise génère l'écart de change attendu.
- **P3**: deux sociétés se consolident avec éliminations et la balance consolidée est équilibrée; l'API est documentée, versionnée et couverte par des tests de contrat.

## 4. P0 · F01 Droits par rôle et verrouillage de périodes

**Objectif.** Garantir que chacun ne fait que ce qu'il a le droit de faire, et qu'une période clôturée ne change plus sans trace. C'est la base de la confiance d'un auditeur et d'un client dans le logiciel.

### Modèle de données

- `roles` (société, nom, système ou personnalisé, liste de permissions) et `memberships` (utilisateur, société, rôle, accès valable du/au, journaux autorisés, expiration éventuelle).
- `period_locks` (société, portée: comptable, TVA ou fin d'exercice; début, fin; statut verrouillé ou déverrouillé; verrouillé par, date, motif; déverrouillé par, date, motif). Le verrouillage TVA de R09 utilise cette table plutôt qu'un mécanisme parallèle.
- Option de société `four_eyes` (validation par une autre personne que l'auteur) et `four_eyes_threshold` (montant à partir duquel la règle s'applique).

### Rôles fournis et permissions

| Capacité | Propriétaire | Comptable | Assistant | Lecteur | Auditeur externe |
| --- | --- | --- | --- | --- | --- |
| Consulter les rapports | Oui | Oui | Oui | Oui | Oui |
| Saisir des brouillons | Oui | Oui | Oui | Non | Non |
| Valider une écriture | Oui | Oui | Non | Non | Non |
| Extourner une écriture validée | Oui | Oui | Non | Non | Non |
| Lettrer et rapprocher | Oui | Oui | Oui | Non | Non |
| Verrouiller une période | Oui | Oui | Non | Non | Non |
| Déverrouiller une période | Oui | Non | Non | Non | Non |
| Gérer plan comptable, TVA, journaux | Oui | Oui | Non | Non | Non |
| Gérer utilisateurs et rôles | Oui | Non | Non | Non | Non |
| Exporter | Oui | Oui | Oui | Configurable | Configurable |
| Consulter la piste d'audit | Oui | Oui | Non | Non | Oui |

Les rôles sont composés de permissions fines (`entries.post`, `periods.unlock`, `reports.export`, etc.). Un propriétaire peut créer un rôle personnalisé à partir de cette liste.

### Règles

- **Contrôle à l'exécution.** Chaque action passe par une policy vérifiée côté serveur, dans l'interface comme dans l'API. Masquer un bouton ne suffit jamais.
- **Effet immédiat.** Un droit retiré s'applique à la requête suivante, sans attendre la fin de la session.
- **Verrouillage en deux couches.** Le service `Ledger::PostEntry` refuse toute écriture datée dans une période verrouillée. Un trigger PostgreSQL rejette en plus tout `INSERT`, `UPDATE` ou `DELETE` sur les lignes d'écritures validées d'une période verrouillée, pour résister aux contournements.
- **Déverrouillage.** Réservé à une permission dédiée, avec motif obligatoire, journalisé, notifié aux propriétaires. Une durée limitée optionnelle reverrouille automatiquement la période.
- **Quatre yeux.** Si `four_eyes` est actif, l'auteur d'une écriture ne peut pas la valider, au-delà du seuil éventuel.
- **Auditeur externe.** Lecture seule, accès à durée limitée, exports désactivables, filigrane du nom de l'utilisateur sur les PDF.
- **Authentification.** Second facteur TOTP obligatoire pour les rôles capables de valider, de déverrouiller ou d'administrer; verrouillage du compte après cinq échecs; connexions et échecs journalisés.
- **Jetons d'API.** Leurs portées reflètent les permissions de leur propriétaire et ne peuvent pas les dépasser.
- **Garde-fous.** Le dernier propriétaire d'une société ne peut être ni retiré ni rétrogradé.

### Interface

- Écran « Utilisateurs et rôles »: liste, invitation par e-mail, matrice de permissions lisible, expiration d'accès.
- Écran « Périodes »: frise mensuelle avec cadenas par mois, par période TVA et par exercice, action de verrouillage groupée.
- Bandeau visible sur toute pièce ou écriture située dans une période verrouillée, avec le motif du verrouillage et le lien vers la demande de déverrouillage.

### Cas limites

- Écriture datée exactement au dernier jour d'une période verrouillée: refusée; au premier jour de la suivante: acceptée.
- Brouillon créé avant le verrouillage et daté dans la période: conservé, non validable, signalé dans R19.
- Utilisateur avec des rôles différents dans deux sociétés: les droits ne se mélangent jamais.
- Migration (F05) et clôture (F10) doivent écrire dans des périodes verrouillées: elles utilisent une fenêtre contrôlée ouverte par un propriétaire, limitée dans le temps, journalisée.
- Fuseau horaire: la date comptable est une date sans heure, indépendante du fuseau de l'utilisateur.

### Critères d'acceptation

1. Un assistant ne peut valider aucune écriture, ni par l'interface ni par l'API (test des deux).
2. Une écriture datée dans une période verrouillée est refusée par le service, et une insertion SQL directe est refusée par le trigger.
3. Déverrouiller sans motif est impossible; avec motif, l'événement figure dans l'audit et notifie les propriétaires.
4. Retirer un droit à un utilisateur connecté prend effet à sa requête suivante.
5. Avec `four_eyes`, l'auteur d'une écriture ne peut pas la valider, et un autre utilisateur le peut.
6. Un auditeur externe expiré est refusé; ses PDF portent son nom en filigrane.
7. Le dernier propriétaire ne peut pas être retiré.
8. Un jeton d'API n'obtient jamais plus de droits que son propriétaire.

**Tests attendus**: policy specs pour chaque permission et chaque rôle, request specs API et interface, spec du trigger avec SQL brut, spec de bord de période (premier et dernier jour), spec d'expiration, spec d'exemple partagé « company scoped » sur toutes les actions.

## 5. P0 · F02 Import CODA et rapprochement bancaire automatique

**Objectif.** Importer les relevés bancaires et rapprocher automatiquement la plus grande part des lignes avec les factures ouvertes, en laissant à un humain les cas incertains. C'est la fonction qui fait gagner ou perdre le plus de temps sur un dossier. Elle s'implémente après F03 (fichiers et pièces) et alimente le rapport R06.

### Modèle de données

- `bank_accounts`: société, IBAN, BIC, compte comptable 55x, journal bancaire, devise.
- `bank_statements`: compte bancaire, numéro de séquence, date, solde d'ouverture, solde de clôture, fichier source, empreinte SHA-256 du fichier, statut.
- `bank_statement_lines`: relevé, date comptable, date de valeur, montant signé, nom et IBAN de la contrepartie, communication structurée, communication libre, référence bancaire, code d'opération, enregistrement brut, empreinte unique, statut (`unmatched`, `suggested`, `matched`, `booked`, `ignored`), ligne d'écriture liée.
- `bank_rules`: société, condition (contient, IBAN, montant), compte, tiers, code TVA, action (proposer ou comptabiliser en brouillon), priorité.
- `import_batches`: fichier, utilisateur, résultat, compteurs (lignes lues, importées, ignorées, en erreur).

### Import du fichier CODA

- Le CODA est un format à enregistrements de largeur fixe. Les types à traiter: 0 (en-tête), 1 (ancien solde), 2 (mouvement, sous-enregistrements 2.1 à 2.3), 3 (informations complémentaires), 4 (message libre), 8 (nouveau solde) et 9 (fin de fichier).
- Détection de l'encodage (souvent ISO-8859-1 ou CP850) et conversion en UTF-8.
- Un fichier peut contenir plusieurs comptes et plusieurs relevés: chacun est importé séparément.
- Le parseur est isolé dans `Banking::Coda::Parser`, testé sur des fichiers réels anonymisés de plusieurs banques. Une interface commune `Banking::StatementParser` permet d'ajouter plus tard CAMT.053 sans toucher au reste.
- L'import est **atomique**: une erreur de structure rejette le fichier entier avec la liste des lignes fautives; rien n'est importé à moitié.

### Idempotence et chaînage

- Un fichier déjà importé (même empreinte) est refusé avec le message « déjà importé le … par … ».
- Un relevé qui recoupe un relevé existant n'importe que les lignes nouvelles, reconnues par leur empreinte (compte, date, montant, référence bancaire, contrepartie, communication).
- Le solde d'ouverture doit égaler le solde de clôture du relevé précédent. Toute rupture est signalée et visible dans R06, sans bloquer l'import.
- Contrôle d'intégrité: ancien solde + somme des mouvements = nouveau solde. En cas d'écart, le relevé est marqué « à vérifier ».

### Rapprochement automatique

Pour chaque ligne non rapprochée, le moteur applique les règles ci-dessous dans cet ordre et retient la première qui produit un résultat, avec un score de confiance.

| Règle | Condition | Confiance |
| --- | --- | --- |
| 1 | Communication structurée (+++xxx/xxxx/xxxxx+++, contrôle modulo 97 valide) égale à celle d'une facture ouverte, montant identique | 100 |
| 2 | Numéro de facture trouvé dans la communication et montant identique | 95 |
| 3 | Montant identique, IBAN de la contrepartie égal à celui du tiers, une seule facture candidate | 90 |
| 4 | Montant identique, nom de la contrepartie proche de celui d'un tiers (similarité `pg_trgm` d'au moins 0,6), une seule candidate | 75 |
| 5 | Paiement groupé: plusieurs factures ouvertes du même tiers dont la somme égale le montant (recherche bornée à 10 factures) | 80 |
| 6 | Règle de `bank_rules` correspondante (frais bancaires, assurances, loyers) | selon la règle |

La communication structurée belge se compose de 10 chiffres suivis de 2 chiffres de contrôle égaux au reste de la division des dix premiers par 97 (97 si le reste est nul).

**Actions selon la confiance**

- 100: rapprochement automatique. L'écriture de paiement (banque 55x contre compte du tiers) est créée et lettrée avec la facture. Elle est **en brouillon** par défaut, et validée seulement si l'option de société `auto_post_exact_bank_matches` est active.
- 75 à 99: proposition affichée, à confirmer par un humain en un clic.
- Moins de 75 ou plusieurs candidates: aucune proposition automatique; la ligne reste à traiter.
- Paiement inférieur à la facture: lettrage partiel avec résiduel. Écart inférieur au seuil de tolérance (paramétrable, défaut 0,05 €): passé en écart d'arrondi sur un compte dédié.
- Virement entre deux comptes de la société: les deux lignes sont appariées via un compte de transit, sans écart.

### Interface

- Écran en deux volets: lignes de relevé à gauche, propositions et écritures ouvertes à droite. Raccourcis clavier pour confirmer, ignorer ou comptabiliser.
- Comptabiliser une ligne inconnue: formulaire prérempli (compte, tiers, TVA), possibilité de ventiler sur plusieurs comptes, et bouton « créer une règle à partir de cette ligne ».
- Indicateurs en tête: lignes importées, taux de rapprochement automatique, lignes à traiter, ancienneté de la plus vieille ligne non rapprochée.
- Chaque rapprochement se défait, avec écriture d'extourne du paiement si elle a été validée.

### Sécurité et audit

- Permission `bank.import` pour importer, `bank.match` pour rapprocher. Le fichier source est stocké via F03 avec un lien signé.
- IBAN masqué dans les journaux; import, rapprochement et défaisage journalisés dans l'audit.

### Cas limites

- Relevé en devise étrangère: rapproché dans la devise du compte, écart de change traité par F11.
- Contrepartie absente (frais, intérêts): rapprochement par règle uniquement.
- Deux factures de même montant pour le même tiers: aucune proposition à 90, choix laissé à l'humain.
- Relevés importés dans le désordre: acceptés, chaînage recalculé.
- Fichier volumineux (plus de 10 000 lignes): traité en tâche de fond avec barre de progression.

### Critères d'acceptation

1. Importer deux fois le même fichier ne crée aucune ligne supplémentaire.
2. Importer un relevé qui recoupe le précédent n'ajoute que les lignes nouvelles.
3. Une rupture de chaînage des soldes est signalée sans bloquer l'import.
4. Sur le jeu de référence de 200 lignes étiquetées, au moins 70 % des lignes sont rapprochées automatiquement, avec zéro faux positif à confiance 100.
5. Un paiement groupé de trois factures est proposé comme une seule action.
6. Un paiement partiel produit un lettrage partiel et le bon résiduel.
7. Défaire un rapprochement restaure l'état des factures et trace l'action.
8. Après l'import et le rapprochement, l'écart de R06 est nul.
9. Un fichier CODA corrompu est rejeté en entier avec les numéros de lignes en cause.

**Tests attendus**: parseur sur fichiers réels anonymisés de plusieurs banques, spec de chaque règle de rapprochement avec ses cas ambigus, spec du modulo 97, spec d'idempotence et de recoupement, spec de non-régression sur le jeu de référence (taux et faux positifs), spec système de l'écran de rapprochement, spec d'invariant I5.

## 6. P0 · F03 Gestion documentaire des pièces justificatives

**Objectif.** Relier chaque écriture à sa pièce, retrouver n'importe quel document en quelques secondes, et conserver les pièces de manière inaltérable pendant la durée légale. Le drill-down des rapports (R02) aboutit ici.

### Modèle de données

- `documents`: société, fichier (ActiveStorage), nom, type MIME, taille, empreinte SHA-256, origine (dépôt manuel, e-mail, Peppol, import bancaire, scan), type de document (facture d'achat, facture de vente, note de crédit, relevé, contrat, autre), statut (boîte de réception, rattaché, archivé), texte extrait (`tsvector`), données extraites (JSON), déposé par, `retention_until`, `legal_hold`, `replaces_id`.
- `document_links`: document, cible polymorphe (écriture, tiers, immobilisation, relevé bancaire, tâche), créé par. Un document peut être lié à plusieurs cibles, et une écriture à plusieurs documents.
- Un fichier n'est jamais modifié. Une nouvelle version est un nouveau document qui pointe l'ancien par `replaces_id`.

### Entrées

- **Boîte de réception**: zone de glisser-déposer multi-fichiers, avec barre de progression par fichier.
- **Adresse e-mail dédiée par société** via ActionMailbox: les pièces jointes arrivent en boîte de réception. Les images en ligne de moins de 10 Ko (logos de signature) sont ignorées; les archives ZIP sont dépliées jusqu'à une limite paramétrable.
- **Autres sources**: Peppol (F06), import bancaire (F02), API `POST /api/v1/documents`.
- **Types acceptés**: PDF, PNG, JPEG, TIFF, XML (UBL), CSV et XLSX. Taille maximale 25 Mo par fichier. Le type réel est vérifié par contenu, pas par extension. Un point d'entrée d'analyse antivirus (ClamAV) est prévu et activable.

### Extraction et propositions

- Pipeline `Documents::Extract` avec extracteurs interchangeables: couche texte du PDF, OCR Tesseract pour les scans, lecture directe pour les XML UBL.
- Champs proposés: fournisseur, numéro de facture, date, montants HTVA, TVA et TTC, échéance, IBAN, communication structurée.
- L'extraction produit des **propositions**, jamais d'écriture validée. Un humain confirme chaque champ, et l'interface montre la zone du document d'où il provient.
- Aucun fichier ne quitte l'infrastructure vers un service externe sans un réglage explicite de société qui l'autorise.
- Un bouton « créer l'écriture » ouvre un brouillon prérempli (via `Ledger::PostEntry`) lié au document.

### Recherche et consultation

- Recherche plein texte PostgreSQL (`unaccent`, configurations fr, nl et en) sur le nom, le texte extrait et les données extraites.
- Filtres: type, tiers, période, montant, statut (non rattaché, rattaché, archivé), origine.
- Visionneuse en panneau latéral (PDF et images): zoom, rotation, téléchargement par lien signé qui vérifie la société et le droit. Filigrane du nom de l'utilisateur pour les auditeurs externes.
- Outil de découpe: un PDF contenant plusieurs factures se scinde par plages de pages en documents enfants.

### Doublons

- Même empreinte SHA-256 dans la société: refus avec un lien vers le document existant.
- Doublon probable (même fournisseur, même numéro de facture, même montant): avertissement bloquant à la création de l'écriture, contournable avec un motif.

### Conservation et intégrité

- Un document lié à une écriture validée ne peut être ni supprimé ni modifié, seulement archivé.
- `retention_until` calculé par type de document; défaut 10 ans, à confirmer avec la réglementation comptable en vigueur. Aucune purge avant ce terme ni pendant une suspension `legal_hold`. La suppression après terme exige une permission dédiée et est auditée.
- Tâche hebdomadaire `documents:verify`: recalcule les empreintes et alerte via R19 si un fichier stocké ne correspond plus.
- Stockage chiffré au repos, compatible S3, sauvegardé avec la base.

### Permissions et audit

Permissions `documents.view`, `documents.upload`, `documents.link`, `documents.archive` et `documents.delete_expired`. Sont journalisés: dépôt, rattachement, détachement, archivage, téléchargement et suppression après terme. La simple consultation n'est pas journalisée.

### Cas limites

- PDF protégé par mot de passe: conservé, marqué « non lisible », sans extraction.
- Scan de mauvaise qualité: l'OCR renvoie une confiance faible et aucune proposition.
- Nom de fichier avec accents ou caractères spéciaux: conservé tel quel à l'affichage, normalisé au stockage.
- Même pièce utile à deux écritures (un relevé, une facture avec acomptes): liens multiples.
- Fichier corrompu: rejeté à l'entrée avec un message clair.

### Critères d'acceptation

1. Depuis R01, on atteint la pièce en trois clics (compte, écriture, pièce), et elle s'affiche dans le panneau latéral.
2. Déposer deux fois le même fichier est refusé, et le message renvoie au document existant.
3. Une pièce liée à une écriture validée ne peut pas être supprimée, seulement archivée.
4. Une recherche par numéro de facture, par nom de tiers et par montant retrouve le document, avec ou sans accents.
5. Un PDF de trois factures se découpe en trois documents liés au parent.
6. Modifier un octet du fichier stocké est détecté par `documents:verify`.
7. Un lien signé d'une autre société est refusé.
8. Un PDF exporté pour un auditeur porte son filigrane.

**Tests attendus**: specs de modèles et de policies, spec ActionMailbox avec pièces jointes multiples, spec d'extraction sur PDF texte, PDF scanné et XML UBL, spec de recherche avec accents, spec d'intégrité, spec système de la visionneuse.

## 7. P1 · F04 Lettrage assisté

**Objectif.** Rapprocher rapidement les factures, notes de crédit et paiements d'un même tiers, avec des suggestions fiables, sans jamais lettrer un montant qui ne se solde pas. Cette fonction rend actionnables les listes de R05 et rend R04 exact.

### Modèle de données

Elle réutilise `reconciliations`, `reconciliation_items(line_id, reconciliation_id, amount)` et `journal_entry_lines.amount_residual` prévus dans la spécification des rapports (§3 et §7), et ajoute:

- `reconciliations.code`: code de lettrage, suite de lettres (A, B, … Z, AA, AB, …) par société et par compte.
- `reconciliations.kind`: `full`, `partial` ou `write_off`.
- `reconciliations.reason` (motif, obligatoire pour un délettrage) et `unreconciled_at`, `unreconciled_by`.
- `reconciliation_suggestions` (société, groupe de lignes, score, règle, statut proposé, accepté ou rejeté, empreinte pour ne pas reproposer un groupe rejeté).

### Services d'écriture

- `Ledger::Reconcile`: prend des lignes, calcule et vérifie, crée la réconciliation et ses items, met à jour les résiduels, dans une seule transaction.
- `Ledger::Unreconcile`: défait la réconciliation, restaure les résiduels et journalise le motif.
- Aucun autre code ne modifie `amount_residual`.

### Règles de lettrage

- Toutes les lignes portent sur le même compte lettrable et le même tiers. Le lettrage entre tiers différents (correction d'erreur d'imputation) exige la permission `reconciliations.cross_partner` et un motif.
- Les lignes de brouillon ne se lettrent pas. Devises différentes: refusé tant que F11 n'est pas livrée.
- **Lettrage total**: Σ débit = Σ crédit sur les lignes choisies. Sinon le bouton reste inactif.
- **Lettrage partiel**: l'utilisateur ou la règle d'imputation (défaut: échéance la plus ancienne d'abord) répartit le montant du paiement. Le résiduel de chaque ligne est mis à jour et rien n'est sur-imputé.
- **Écart d'arrondi**: si l'écart absolu est inférieur ou égal au seuil de société (défaut 0,05 €), une écriture d'écart de régularisation est créée en brouillon sur un compte dédié, et le lettrage est total.
- Le lettrage ne modifie aucun montant comptable. Il reste possible dans une période verrouillée, avec journalisation. Le délettrage d'une ligne située dans une période verrouillée exige `reconciliations.unreconcile_locked`.

### Suggestions

`Reconciliation::Suggester` regroupe les lignes ouvertes par compte et par tiers, puis applique ces règles, classées par score.

| Règle | Condition | Score |
| --- | --- | --- |
| 1 | Paire opposée de même montant avec la même communication structurée ou la même référence | 100 |
| 2 | Facture et note de crédit portant la même référence de document | 95 |
| 3 | Paire opposée de même montant, dates les plus proches | 90 |
| 4 | Groupe équilibré: toutes les lignes ouvertes d'un tiers se soldent à zéro | 85 |
| 5 | Une ligne contre une combinaison de plusieurs lignes de somme égale (recherche bornée à 8 lignes) | 80 |
| 6 | Paire dont l'écart est inférieur ou égal au seuil d'arrondi | 70 |

- Les suggestions sont recalculées à la demande et chaque nuit. Un groupe rejeté n'est pas reproposé tant que ses lignes ne changent pas (empreinte).
- Option `auto_reconcile_exact`: un job nocturne applique seul les suggestions de score 100. Aucune autre n'est appliquée sans confirmation humaine. Chaque lettrage automatique est marqué comme tel et se défait comme les autres.

### Interface

- Écran « Lettrage »: choix du compte et du tiers, deux colonnes (débits et crédits) avec cases à cocher, somme et écart calculés en direct, bouton « Lettrer » actif seulement quand le lettrage est valide.
- Panneau de suggestions avec score, règle et bouton d'acceptation en un clic; accepter plusieurs suggestions en lot montre d'abord un aperçu à confirmer.
- Filtres: ancienneté, montant, état; raccourcis clavier pour cocher, lettrer et passer au tiers suivant.
- Sur chaque ligne du grand livre (R02): code de lettrage cliquable, avec l'historique des lettrages et délettrages de la ligne.

### Cas limites

- Ligne déjà partiellement lettrée: seul son résiduel est proposé.
- Paiement supérieur à la facture: le surplus reste ouvert comme acompte non affecté du tiers.
- Trois factures et deux paiements dont la somme se solde: lettrage groupé accepté, avec suggestion de règle 4.
- Deux lettrages simultanés sur la même ligne (deux utilisateurs): le second est refusé proprement par verrou d'enregistrement.
- Ligne appartenant à un exercice déjà clôturé: lettrable, avec journalisation.

### Critères d'acceptation

1. Un lettrage dont Σ débit ≠ Σ crédit est refusé, sauf partiel ou écart d'arrondi explicite.
2. Après un lettrage partiel, le résiduel de chaque ligne est exact et R04 le reflète.
3. Sur le jeu de référence, les suggestions de score 100 sont toutes justes (zéro faux positif) et couvrent les paires exactes.
4. Un groupe rejeté ne réapparaît pas avant que ses lignes changent.
5. Un délettrage exige un motif et restaure les résiduels et R04 à leur état antérieur.
6. Deux utilisateurs lettrant la même ligne au même moment: un seul réussit.
7. `auto_reconcile_exact` n'applique que des suggestions de score 100 et laisse une trace dans l'audit.
8. L'invariant I4 reste vert après toute opération de lettrage.

**Tests attendus**: specs de `Ledger::Reconcile` et `Unreconcile` avec tableaux de cas (total, partiel, écart, surplus), spec du suggester avec des cas ambigus, spec de concurrence, spec de non-régression sur le jeu de référence, spec système de l'écran de lettrage.

## 8. P1 · F05 Migration depuis WinBooks

**Objectif.** Reprendre un dossier existant (plan comptable, tiers, soldes, historique, lignes ouvertes) sans perte et avec la preuve que les chiffres sont identiques. Sans migration fiable, personne ne change de logiciel. Ses données servent aussi de contrôle final pour les rapports R07 à R09.

**Point d'attention pour l'agent.** Le format exact des exports WinBooks n'est pas décrit dans ce document. L'utilisateur fournit un dossier réel exporté et anonymisé. L'agent en dérive l'adaptateur et documente ce qu'il a observé (fichiers, colonnes, encodage). Il n'invente aucun nom de table ou de colonne.

### Architecture

- Un **format canonique** intermédiaire (tables de staging `migration_*`) décrit toutes les données à reprendre. Chaque source a son **adaptateur** (`Migration::Adapters::Winbooks`, `Migration::Adapters::GenericCsv`) qui la convertit vers ce format. Ajouter une source ne touche ni le moteur ni le contrôle.
- Le moteur lit le staging, applique le mapping, écrit dans le grand livre par les services de F01 et de la spécification des rapports (`Ledger::PostEntry`), puis produit le rapport de vérification.
- Statuts d'une migration: `staged` → `mapped` → `imported` → `verified` → `committed`. Tant que le statut n'est pas `committed`, tout est annulable par un retour arrière complet.

### Données reprises

| Bloc | Contenu | Obligatoire |
| --- | --- | --- |
| Société et exercices | Identité, numéro BCE, exercices avec dates, statut | Oui |
| Plan comptable | Numéro, libellé, classe, type (lettrable, banque, TVA), sens normal | Oui |
| Journaux | Code, libellé, type, compte de contrepartie | Oui |
| Tiers | Nom, numéro de TVA, IBAN, adresse, conditions de paiement, type | Oui |
| Codes TVA | Correspondance vers `vat_codes` et grilles | Oui |
| Soldes d'ouverture | À-nouveaux par compte et par tiers | Oui |
| Écritures | Historique complet d'un nombre d'exercices choisi | Option |
| Lignes ouvertes | Factures et paiements non lettrés avec échéances | Oui |
| Lettrages | Codes et groupes historiques | Option |
| Immobilisations | Registre et plans d'amortissement | Option |
| Pièces | Liens vers les fichiers si fournis | Option |

Deux modes: **soldes d'ouverture seulement** (les soldes au début de l'exercice courant, plus les lignes ouvertes) ou **historique complet** sur N exercices.

### Étapes

1. **Préparation**: création de la société, des exercices et des paramètres.
2. **Extraction**: l'adaptateur lit les fichiers, remplit le staging, sans rien écrire dans le grand livre.
3. **Mapping**: comptes, journaux, tiers et codes TVA sont mis en correspondance. Un écran propose des correspondances automatiques par numéro et par libellé, et laisse corriger les autres. Les comptes de la source absents du plan cible sont créés ou reliés sur décision explicite.
4. **Simulation** (`dry-run`): tout le traitement s'exécute dans une transaction annulée à la fin. Seul le rapport de vérification est produit.
5. **Import réel**: une transaction par exercice, dans une fenêtre de verrouillage contrôlée ouverte par un propriétaire (F01).
6. **Vérification**: comparaison automatique entre la source et LedgerFlow (voir plus bas).
7. **Confirmation**: un propriétaire passe la migration en `committed`. Les exercices importés sont alors verrouillés et le lot est figé dans l'audit.

### Traçabilité

- Chaque objet importé porte `source_system`, `source_id` et `migration_batch_id`; les écritures gardent leur numéro d'origine dans `legacy_number`, et la numérotation continue là où la source s'est arrêtée.
- L'audit reçoit une entrée par lot et par type d'objet, avec les compteurs, plutôt qu'une ligne par ligne d'écriture. La table `imported_objects` conserve le détail.
- Une clé d'idempotence (`source_system`, `source_id`, société) garantit qu'une relance n'importe rien deux fois.

### Vérifications automatiques

Le rapport de migration, exportable en PDF et XLSX, contient:

- Nombre d'écritures, de lignes, de tiers et de comptes: source contre LedgerFlow.
- Total débit et total crédit par exercice, et solde de chaque compte à chaque fin de période.
- Balance âgée des clients et des fournisseurs (total et par tiers) contre les lignes ouvertes de la source.
- Grilles TVA par période, si la source les fournit.
- Liste d'anomalies: écritures déséquilibrées dans la source, comptes inconnus, tiers sans numéro de TVA valide, dates hors exercice, doublons probables, lettrages incohérents.

Une écriture déséquilibrée dans la source n'est jamais corrigée en silence. Elle bloque l'import de sa pièce et attend une décision: correction du mapping, ou acceptation avec une écriture d'écart de migration sur un compte dédié, marquée `imported_adjustment` et listée dans le rapport.

### Sécurité

Seul un propriétaire peut lancer une migration (`migration.run`). Les fichiers sources sont stockés via F03, chiffrés, avec durée de conservation limitée paramétrable.

### Cas limites

- Encodage des fichiers sources (ANSI, OEM ou UTF-8): détecté et documenté.
- Compte de la source à la fois lettrable et non lettrable selon l'exercice: signalé, jamais deviné.
- Tiers en double dans la source (même numéro de TVA, noms proches): proposés à la fusion, jamais fusionnés seuls.
- Volume: 500 000 lignes importées en moins de dix minutes (insertions par lots).
- Import interrompu: reprise à partir du dernier exercice complet, sans doublon.

### Critères d'acceptation

1. Sur le dossier de référence, la balance de chaque compte égale celle de la source à l'euro près, à chaque fin de mois.
2. Le total des lignes ouvertes clients et fournisseurs égale celui de la source, et R04 reproduit la balance âgée de la source.
3. La simulation n'écrit rien en base: comptages inchangés avant et après.
4. Le retour arrière avant `committed` supprime tout ce qu'a créé le lot et rien d'autre.
5. Relancer le même import ne crée aucun doublon.
6. Une écriture déséquilibrée de la source est bloquée et listée, jamais corrigée en silence.
7. Après `committed`, les exercices importés sont verrouillés et le lot est retrouvable dans l'audit.
8. Les 500 000 lignes s'importent en moins de dix minutes.

**Tests attendus**: specs d'adaptateur sur un échantillon réel anonymisé, spec du moteur sur un dossier synthétique de 5 000 lignes avec anomalies volontaires, spec de simulation, de retour arrière et d'idempotence, test de charge à 500 000 lignes, spec de comparaison automatique avec un cas d'écart voulu.

## 9. P1 · F06 Facturation électronique Peppol

**Objectif.** Recevoir les factures et notes de crédit Peppol sous forme de brouillons d'écriture prêts à valider, et envoyer les factures de vente par le même canal, avec une traçabilité complète. Une intégration Peppol via Digiteal existe déjà: cette fonction commence donc par un **audit**, puis étend l'existant. Elle ne le réécrit pas.

### Étape 0: audit de l'existant

Avant de coder, l'agent produit `docs/features/F06-audit.md` qui décrit ce qui est déjà en place: authentification auprès de Digiteal, enregistrement des participants (identifiant Peppol de la société), réception (webhook ou interrogation), envoi, suivi des statuts, gestion des erreurs, environnements de test et de production. Il liste ensuite les écarts avec cette section et propose l'ordre des travaux. Il s'arrête et attend validation avant de modifier le code existant.

### Modèle de données

- `peppol_messages`: société, sens (entrant, sortant), identifiant de message, identifiants Peppol de l'expéditeur et du destinataire, type de document, processus, statut, référence Digiteal, document XML lié (F03), date de réception ou d'envoi, écriture liée, erreurs.
- `peppol_participants`: société, identifiant Peppol (schéma et valeur), statut d'enregistrement.
- `supplier_defaults`: tiers, dernier compte de charge utilisé, code TVA, journal, conditions de paiement. Alimente les propositions de comptes.
- `vat_category_mappings`: catégorie TVA UBL (S, Z, E, AE, K, G, O) et taux vers un `vat_code` de la société (donnée modifiable, pas de valeur codée en dur).

### Réception

1. Le message entrant est enregistré avec son identifiant. Un message déjà reçu est ignoré (idempotence par identifiant de message).
2. Le XML est stocké dans F03, avec le PDF intégré s'il existe. Sans PDF, un rendu lisible est généré à partir du XML.
3. Le mappeur `Peppol::InvoiceMapper` lit l'UBL 2.1 (Peppol BIS Billing 3.0, factures et notes de crédit) et produit une facture canonique: fournisseur (nom, TVA, numéro BCE, IBAN, adresse), numéro, dates, devise, lignes (description, quantité, prix, catégorie et taux de TVA, montant), remises et frais au niveau document, totaux HTVA, TVA et TTC, moyen de paiement et communication structurée.
4. **Contrôles automatiques**: somme des lignes égale au total HTVA; TVA recalculée par catégorie avec une tolérance de 0,01 €; numéro de TVA belge valide (modulo 97); devise connue; échéance cohérente; doublon (même fournisseur, même numéro).
5. **Tiers**: recherche par numéro de TVA, numéro BCE, puis IBAN. Un fournisseur inconnu est créé avec le statut « à valider ». Jamais créé comme validé automatiquement.
6. **Brouillon d'écriture** dans le journal d'achats, via `Ledger::PostEntry`: une ligne de charge par catégorie de TVA (ou par ligne si les comptes diffèrent), lignes de TVA avec les codes de `vat_category_mappings`, ligne de dette fournisseur (compte 440) portant l'échéance et la communication structurée. Comptes proposés d'après `supplier_defaults`, sinon d'après les règles de la société.
7. Un message qui échoue à un contrôle passe en `needs_review` avec les raisons affichées. Il n'est jamais supprimé ni validé.
8. La communication structurée de la facture est conservée sur la ligne de dette: elle nourrit la règle 1 du rapprochement bancaire (F02) et de F04.

Une note de crédit crée un brouillon inverse, lié à la facture d'origine si sa référence est fournie, avec proposition de lettrage (F04).

### Émission

- À partir d'une facture de vente validée (ou du module de facturation existant): génération de l'UBL BIS Billing 3.0, avec le PDF en pièce jointe.
- **Validation avant envoi** contre les règles officielles Peppol (schematron). Le moyen de la mettre en œuvre est une décision à prendre avec l'utilisateur: service de validation du fournisseur d'accès, ou schematron exécuté par un utilitaire local. L'agent présente les deux options avec leurs coûts avant de choisir.
- Vérification du destinataire dans l'annuaire Peppol (SMP) via l'API du fournisseur d'accès. S'il n'est pas joignable par Peppol, repli proposé: envoi du PDF par e-mail, tracé dans l'audit.
- Statuts: brouillon → envoyé → livré → accusé, ou échec. Trois tentatives avec attente croissante en cas d'erreur technique; une erreur de validation n'est jamais rejouée telle quelle.
- Le XML envoyé et l'accusé sont stockés dans F03 et liés à l'écriture.

### Interface

- « Factures reçues »: liste filtrable par statut, aperçu du PDF et du XML côte à côte, action « créer le brouillon » (en lot pour les messages sans anomalie), écran de correction pour `needs_review`.
- « Factures envoyées »: statut de livraison, erreurs lisibles, action de renvoi.
- Tableau de suivi: reçues, en attente, en anomalie, envoyées, en échec, sur la période.
- Réglages: participant Peppol, mappings TVA, règles de proposition de comptes.

### Sécurité

- Les webhooks sont authentifiés (signature HMAC vérifiée, liste blanche d'adresses si le fournisseur en publie). Secrets dans `credentials`, jamais dans le dépôt.
- Environnements de test et de production strictement séparés, avec un bandeau visible en test.
- Permissions `peppol.review`, `peppol.send` et `peppol.configure`. Tout envoi, création de brouillon et changement de réglage est journalisé.

### Cas limites

- Documents Peppol qui ne sont pas des factures (commande, avis d'expédition): stockés, sans écriture.
- Facture avec remise ou frais au niveau du document: répartis selon la catégorie de TVA, avec un test d'égalité des totaux.
- Catégorie de TVA inconnue ou autoliquidation (AE): brouillon avec code d'autoliquidation si mappé, sinon `needs_review`.
- Facture en devise étrangère: traitée après F11, en `needs_review` avec un message clair d'ici là.
- Même facture reçue par Peppol et par e-mail: signalée comme doublon.
- Le message arrive deux fois: un seul enregistrement.

### Critères d'acceptation

1. Les fichiers d'exemple officiels Peppol BIS Billing 3.0 (facture, note de crédit, remises, autoliquidation) produisent des brouillons dont les totaux égalent ceux du XML.
2. Un message reçu deux fois ne crée qu'un enregistrement et qu'un brouillon.
3. Une facture aux totaux incohérents passe en `needs_review` avec la raison, sans brouillon.
4. Un fournisseur inconnu est créé « à valider »; un fournisseur connu par son numéro de TVA est réutilisé.
5. La communication structurée de la facture reçue permet le rapprochement automatique de la règle 1 du paiement dans F02.
6. Une facture de vente est refusée à l'envoi si la validation Peppol échoue, et l'erreur est lisible.
7. Un webhook à la signature invalide est rejeté et journalisé.
8. Aucun brouillon créé par cette fonction n'est validé sans action humaine.

**Tests attendus**: spec du mappeur sur les exemples officiels, spec des contrôles, spec d'idempotence, spec de webhook signé et falsifié, spec du générateur UBL et de sa validation, spec système de « Factures reçues », stub HTTP de Digiteal pour tous les cas d'erreur.

## 10. P1 · F07 Écritures récurrentes, modèles et extourne

**Objectif.** Supprimer la saisie répétitive (loyers, assurances, dotations, frais) et corriger proprement une écriture validée par une extourne tracée. Cette fonction fournit aussi le service `Ledger::ReverseEntry` dont dépendent F04, F10 et R17.

### Modèle de données

- `entry_templates`: société, nom, journal, lignes modèles (compte, tiers éventuel, débit ou crédit, montant fixe, pourcentage ou saisie, code TVA, libellé avec variables `{mois}`, `{année}`, `{période}`).
- `recurring_entries`: modèle, fréquence (mensuelle, trimestrielle, annuelle), jour (numéro du mois ou dernier jour), début, fin éventuelle, nombre maximal d'occurrences, prochaine date, mode (`draft` par défaut, `post` en option), indexation annuelle en pourcentage, `feeds_cash_forecast` (alimente R14), statut (active, en pause, terminée, bloquée).
- `recurring_runs`: échéance, écriture générée, statut, erreur. Clé d'unicité (`recurring_id`, date d'échéance).
- `journal_entries.reverses_entry_id`, `reversed_by_entry_id` et `auto_reverse_on`.

### Modèles d'écriture

- « Nouvelle écriture depuis un modèle »: les champs variables sont demandés, l'écriture est créée en brouillon et doit être équilibrée avant validation.
- Modèles fournis en exemple: loyer, assurance annuelle (avec report de charge), dotation aux amortissements, frais bancaires, régularisation de TVA.

### Écritures récurrentes

- Le job quotidien `Recurring::Generate` crée les écritures dont l'échéance est atteinte, avec un délai d'anticipation paramétrable (défaut 0 jour). Il est **idempotent**: relancer le job ne crée aucun doublon.
- **Rattrapage**: après une interruption, les échéances manquées sont générées jusqu'à une limite de 12 occurrences, puis signalées.
- **Mode brouillon** par défaut: l'écriture attend une validation humaine. Le mode `post` n'est autorisé que pour un modèle à montant fixe approuvé par un propriétaire.
- **Période verrouillée** à l'échéance: la génération est suspendue, le statut passe à `bloquée`, les propriétaires sont notifiés. Rien n'est daté ailleurs à leur place.
- **Indexation**: au premier jour de chaque année d'application, le montant est majoré du pourcentage, avec arrondi au centime et journalisation de l'ancien et du nouveau montant.
- **Aperçu**: liste des douze prochaines échéances avec leur montant et le total mensuel, pour repérer une dérive.
- Les récurrentes qui portent `feeds_cash_forecast` alimentent le prévisionnel R14 sans double saisie.

### Extourne

`Ledger::ReverseEntry` crée une écriture inverse d'une écriture validée.

- **Motif obligatoire**. Référence automatique « Extourne de l'écriture n° … », lien bidirectionnel entre les deux écritures, l'originale n'est jamais modifiée.
- **Date**: par défaut la date d'origine si sa période est ouverte, sinon le premier jour de la première période ouverte. La date reste modifiable dans une période ouverte.
- **Une seule extourne active** par écriture. Extourner une extourne est permis et recrée une écriture identique à l'originale.
- **Lettrage**: si des lignes de l'écriture sont lettrées, l'utilisateur doit confirmer le délettrage préalable, exécuté par `Ledger::Unreconcile` avec le même motif.
- **TVA**: une extourne dans une période TVA déjà déposée est datée dans la période ouverte suivante et marquée comme régularisation (grilles de régularisation de R09).
- **Extourne planifiée**: `auto_reverse_on` génère l'extourne en brouillon à la date choisie. R17 s'en sert pour les régularisations de clôture.
- Le brouillon d'extourne planifiée, comme tout brouillon, n'est jamais validé sans action humaine.

### Interface

- Bouton « Extourner » sur une écriture validée, avec aperçu des lignes inverses, champ de motif et avertissements (lettrage, TVA, période).
- Écran « Récurrentes »: liste, prochaine échéance, dernière génération, statut, pause et reprise, aperçu des douze mois.
- Bouton « Dupliquer » sur toute écriture: crée un brouillon, sans lien de réversion.

### Sécurité et audit

Permissions `entry_templates.manage`, `recurring.manage`, `recurring.approve_post` et `entries.reverse`. Création, modification, pause, indexation, génération et extourne sont journalisées avec l'auteur ou le job, et le motif pour l'extourne.

### Cas limites

- Échéance le 31 dans un mois de 30 jours: dernier jour du mois.
- Modèle dont un compte est archivé: la génération échoue proprement, le statut passe à `bloquée` avec la raison.
- Écriture récurrente supprimée alors qu'elle a déjà généré des écritures: les écritures restent, le lien de provenance est conservé.
- Deux instances du job lancées en même temps: la clé d'unicité garantit une seule écriture par échéance.
- Extourne d'une écriture d'un exercice clôturé: datée dans l'exercice ouvert, avec avertissement clair.

### Critères d'acceptation

1. Relancer `Recurring::Generate` trois fois le même jour ne crée qu'une écriture par échéance.
2. Après une interruption de trois mois, trois occurrences sont rattrapées, en brouillon, avec leurs dates correctes.
3. Une échéance dans une période verrouillée ne génère rien et notifie les propriétaires.
4. L'indexation de 3 % d'un loyer de 1 000 € donne 1 030,00 € à la date prévue, avec trace.
5. Extourner une écriture produit des lignes exactement inverses et un solde nul pour l'ensemble des deux écritures sur chaque compte concerné.
6. Une seconde extourne de la même écriture est refusée, tant que la première est active.
7. Extourner une écriture lettrée exige la confirmation de délettrage et restaure R04 après l'opération.
8. Un mode `post` refusé pour un modèle non approuvé.

**Tests attendus**: specs de `Ledger::ReverseEntry` sur tableau de cas (période ouverte, verrouillée, TVA déposée, lettrée), spec d'idempotence du job avec `travel_to`, spec de rattrapage, spec d'indexation, spec de concurrence, spec système du bouton « Extourner ».

## 11. P2 · F08 Tâches et commentaires, F09 Relances clients

F08 retire les échanges de suivi des e-mails et les rattache à l'objet concerné. F09 s'appuie dessus pour piloter le recouvrement.

### F08 Tâches et commentaires

**Objectif.** Noter, assigner et suivre ce qui reste à faire sur une écriture, un compte, un tiers ou un document (« pièce manquante », « à vérifier avec le client »), sans quitter le logiciel.

**Modèle de données**

- `tasks`: société, titre, description, statut (ouverte, en cours, bloquée, terminée, annulée), priorité, personne assignée, échéance, type (pièce manquante, à vérifier, question client, clôture, autre), cible polymorphe (écriture, compte, tiers, document, ligne de relevé, période), auteur, date et auteur de clôture.
- `comments`: cible polymorphe, auteur, texte, mentions, résolu ou non.
- `notifications`: destinataire, événement, lu ou non, canal.

**Fonctionnement**

- Créer une tâche depuis n'importe quel écran: écriture, ligne du grand livre, ligne de relevé, tiers, document, anomalie de R19, ligne de R05. La cible est préremplie.
- Écrans « Mes tâches » et « Toutes les tâches », avec filtres par statut, échéance, personne, cible et société.
- Un badge sur les écritures et les tiers indique le nombre de tâches ouvertes; R02 et R05 affichent une icône cliquable sur les lignes concernées.
- Commentaires en fils de discussion, avec mentions `@utilisateur` et résolution. Un commentaire n'est modifiable que par son auteur pendant 15 minutes; il n'est jamais supprimé, seulement masqué, avec trace dans l'audit.
- Commenter ou créer une tâche sur une écriture validée ne modifie pas l'écriture.
- Notifications dans l'application et par e-mail, avec récapitulatif quotidien configurable et rappel avant échéance.
- **Réponse d'un tiers externe** (option): une question à un client génère un lien signé à durée limitée; il permet de répondre par texte et de joindre des fichiers, qui arrivent dans la boîte de réception de F03. Ce lien ne donne accès à aucune autre donnée.

**Permissions**: `tasks.manage` et `comments.write`. La visibilité d'une tâche suit celle de sa cible.

**Critères d'acceptation**

1. Une tâche créée depuis une ligne du grand livre est liée à cette ligne et apparaît en badge sur l'écriture.
2. Une mention notifie la bonne personne, une seule fois.
3. Un utilisateur sans droit sur la cible ne voit ni la tâche ni ses commentaires.
4. Un commentaire ne se modifie plus après 15 minutes et ne se supprime pas.
5. Le lien de réponse d'un tiers expire à la date prévue et ne donne accès à rien d'autre.
6. Créer une tâche depuis une anomalie de R19 la relie à cette anomalie; la clôturer ne l'acquitte pas seule.

### F09 Relances clients

**Objectif.** Transformer la balance âgée en relances envoyées, tracées et suivies, sans jamais envoyer de courrier sans validation humaine.

**Modèle de données**

- `dunning_policies`: paliers (défaut: niveau 1 rappel amiable à J+7 après l'échéance, niveau 2 à J+21, niveau 3 mise en demeure à J+45), modèles de texte par niveau et par langue (fr, nl, en) avec variables, seuil de montant minimum, frais de relance optionnels.
- `dunning_runs`: société, date, auteur, statut (préparée, envoyée).
- `dunning_items`: campagne, tiers, niveau, lignes concernées, total, canal (e-mail ou courrier), date d'envoi, identifiant de message, statut (envoyé, rebond, ouvert si disponible).
- Sur les lignes: `disputed` (litige), `payment_promised_on`, `dunning_level` et `last_dunned_at`.

**Fonctionnement**

1. À partir de R04 ou R05, « Préparer les relances » sélectionne les factures échues, non lettrées, au-dessus du seuil, ni en litige ni sous promesse de paiement non échue.
2. Les factures sont regroupées par tiers. Le niveau proposé dépend du plus ancien retard et du dernier niveau déjà envoyé; il ne saute jamais un niveau sans confirmation.
3. Aperçu tiers par tiers: lettre (PDF rendu par Ferrum) ou e-mail, relevé de compte des lignes ouvertes en pièce jointe, factures d'origine issues de F03.
4. L'utilisateur coche, modifie ou exclut, puis valide. **Aucun envoi sans cette validation.** Une option `auto_send_level_1`, désactivée par défaut, peut être activée par un propriétaire pour le seul niveau 1.
5. Chaque envoi met à jour l'historique du tiers et crée une tâche de suivi F08 à une échéance choisie (défaut: 7 jours).
6. Une promesse de paiement saisie exclut les factures concernées jusqu'à sa date, puis les réintègre avec une tâche.

**Intérêts et indemnités.** Les intérêts de retard et l'indemnité forfaitaire dépendent de la réglementation et du contrat. Ils sont **paramétrables et désactivés par défaut**. L'agent n'y met aucun taux légal: les valeurs sont saisies par le comptable et documentées dans `QUESTIONS.md`.

**Sécurité et conformité**: permission `dunning.send` distincte de `dunning.prepare`; adresse d'expédition et signatures d'e-mail paramétrées par société (SPF et DKIM documentés); tiers marqués « ne pas relancer » exclus; rebonds journalisés; envoi tracé dans l'audit.

**Cas limites**

- Tiers sans adresse e-mail: proposé en courrier PDF à imprimer.
- Facture partiellement payée: relance sur le résiduel uniquement.
- Note de crédit en attente d'affectation: signalée sur le relevé, non déduite d'office.
- Deux campagnes le même jour pour un même tiers: la seconde est refusée avec un lien vers la première.

**Critères d'acceptation**

1. Une facture en litige, sous promesse non échue ou en dessous du seuil n'est jamais proposée.
2. Le niveau proposé ne saute pas de palier sans confirmation explicite.
3. Rien n'est envoyé avant validation; avec `auto_send_level_1` actif, seul le niveau 1 part seul.
4. La lettre et le relevé de compte reprennent exactement les montants de R04 pour le tiers.
5. Après envoi, l'historique du tiers est à jour et une tâche de suivi existe.
6. Un rebond d'e-mail est journalisé et signalé sur le tiers.
7. Deux campagnes le même jour pour un tiers sont refusées.

**Tests attendus (F08 et F09)**: policies et visibilité, spec de notifications et de mentions, spec du lien signé externe, spec de sélection des factures avec tableau de cas (litige, promesse, seuil, résiduel), spec de rendu PDF et e-mail, stub d'envoi avec cas de rebond, spec système du parcours de préparation à l'envoi.

## 12. P2 · F10 Clôture d'exercice guidée

**Objectif.** Conduire l'utilisateur de l'exercice ouvert à l'exercice clôturé par une liste d'étapes contrôlées, sans étape cachée: contrôles automatiques, écritures de clôture en brouillon, reprise des à-nouveaux, verrouillage et dossier de clôture. Cette fonction orchestre les rapports et fonctions précédents; elle ne recalcule rien.

### Modèle de données

- `closing_runs`: société, exercice, statut (`draft`, `in_progress`, `ready`, `closed`, `reopened`), ouverte par, clôturée par, dates.
- `closing_steps`: clôture, code, titre, type (`check`, `action`, `manual`, `report`), bloquante ou non, statut (`pending`, `ok`, `warning`, `blocked`, `skipped`, `done`), résultat en JSON, auteur et date, commentaire.
- `closing_snapshots`: contenu JSON de la balance, du bilan et du compte de résultat à la clôture, avec son empreinte SHA-256.
- Paramètres `closing_accounts`: comptes de résultat et d'affectation utilisés pour les écritures de clôture, définis par société. L'agent propose des valeurs d'après le PCMN, les consigne dans `QUESTIONS.md` et ne les applique qu'après validation par le comptable.

### Les étapes

| N° | Étape | Type | Bloquante | Contrôle ou action |
| --- | --- | --- | --- | --- |
| 1 | Préparation | action | Oui | L'exercice suivant existe; sinon création proposée |
| 2 | Saisie complète | check | Oui | Aucun brouillon dans l'exercice, aucune tâche de type « clôture » ouverte (ou acquittées avec commentaire) |
| 3 | Banque | check | Oui | Rapprochement figé (R06) et écart nul pour chaque compte bancaire au dernier jour |
| 4 | Tiers | check | Oui | Aucun groupe équilibré non lettré (R05); balance âgée égale aux comptes 400 et 440 (I4) |
| 5 | TVA | check | Oui | Toutes les périodes TVA de l'exercice déposées et verrouillées (R09) |
| 6 | Immobilisations | action | Oui | Dotations générées et validées; I10 vert (R16) |
| 7 | Régularisations | action | Oui | Charges et produits à reporter, à imputer, factures à recevoir validés; extournes planifiées; I11 vert (R17) |
| 8 | Stocks | manual | Non | Variation de stock saisie, avec commentaire |
| 9 | Provisions et créances douteuses | manual | Non | Réductions de valeur et provisions saisies ou déclarées sans objet |
| 10 | Impôts | manual | Non | Charge d'impôt de l'exercice saisie ou déclarée sans objet |
| 11 | Comptes d'attente | check | Oui | Comptes d'attente et de liaison à solde nul |
| 12 | Réévaluation des devises | action | Oui | Écarts de change de clôture générés (actif dès la livraison de F11) |
| 13 | Cohérence | check | Oui | Aucune anomalie bloquante dans R19; avertissements acquittés; invariants I1 à I11 verts |
| 14 | Revue analytique | report | Non | R07 et R08 avec N-1; chaque rubrique variant de plus de 20 % et de plus de 1 000 € porte un commentaire |
| 15 | Écritures de clôture | action | Oui | Clôture des comptes de résultat vers les comptes de `closing_accounts`, en brouillon puis validation par lot |
| 16 | À-nouveaux | action | Oui | Écriture d'ouverture de l'exercice suivant pour les classes 0 à 5, avec reprise des lignes ouvertes des tiers une à une |
| 17 | Verrouillage et dossier | action | Oui | Verrou de l'exercice et de ses mois (F01), instantané figé, liasse de clôture (R20) |
| 18 | Approbation | manual | Oui | Un propriétaire approuve; avec `four_eyes`, ce ne peut pas être la personne qui a préparé la clôture |

Les seuils de l'étape 14 (20 % et 1 000 €) sont des paramètres de société.

### Règles

- Chaque contrôle s'exécute en direct en appelant les services des rapports concernés et peut être relancé à tout moment. Un résultat n'est conservé que dans l'instantané final.
- Une étape **bloquante** en `blocked` empêche la clôture. Une étape en `warning` se poursuit après acquittement avec un commentaire. Une étape non bloquante peut être `skipped` avec un motif.
- Les étapes manuelles exigent une confirmation et un commentaire de la personne.
- Toutes les écritures produites par la clôture passent par `Ledger::PostEntry` en **brouillon** et se valident en lot par une personne disposant de `entries.post`, après aperçu des lignes.
- **À-nouveaux détaillés**: les lignes ouvertes des comptes 400 et 440 sont reprises une à une, avec leur tiers, leur échéance et leur référence d'origine (`origin_line_id`), afin que la balance âgée au premier jour du nouvel exercice reste identique à celle du dernier jour de l'ancien.
- La fenêtre d'écriture dans une période verrouillée de F01 est utilisée pour les étapes 15 et 16, ouverte par un propriétaire, limitée dans le temps et journalisée.

### Réouverture

- Réservée à un propriétaire, avec motif obligatoire, journalisée, notifiée.
- Elle déverrouille l'exercice, passe la clôture en `reopened` et marque les à-nouveaux de l'exercice suivant « à recalculer ».
- **Recalcul des à-nouveaux**: action idempotente qui extourne l'écriture d'ouverture (`Ledger::ReverseEntry`), génère la nouvelle, et affiche d'abord les différences par compte.
- La réouverture est refusée si l'exercice suivant est déjà clôturé.

### Interface

- Assistant en colonne de gauche avec la progression en pourcentage et un badge par étape; chaque étape ouvre un panneau avec le résultat, le lien vers le rapport concerné et les actions possibles.
- Récapitulatif final: résultat de l'exercice, total du bilan, principales variations, et effet sur l'ouverture de l'exercice suivant.
- Le dossier de clôture est la liasse R20, téléchargeable avec son manifeste de hachages.

### Cas limites

- Premier exercice, plus court ou plus long que douze mois: les étapes et les seuils s'adaptent, avec avertissement de comparabilité.
- Exercice suivant absent: créé à l'étape 1, avec confirmation.
- Tiers archivé ayant encore des lignes ouvertes: repris tel quel, avec un avertissement.
- Interruption au milieu de l'étape 15 ou 16: reprise sans doublon grâce à une clé d'idempotence par étape.

### Critères d'acceptation

1. Sur le jeu de référence, la clôture s'exécute de l'étape 1 à l'étape 18 sans intervention hors des étapes manuelles.
2. Soldes d'ouverture de l'exercice suivant = soldes de clôture des classes 0 à 5; les comptes de résultat s'ouvrent à zéro.
3. R04 au premier jour du nouvel exercice égale R04 au dernier jour de l'ancien, tiers par tiers.
4. Une étape bloquante non résolue empêche le passage en `closed`.
5. Aucune écriture de clôture n'est validée sans action humaine.
6. Après clôture, toute écriture dans l'exercice est refusée, y compris par SQL direct (trigger de F01).
7. La réouverture puis le recalcul restituent des à-nouveaux corrects, avec la liste des différences.
8. Avec `four_eyes`, la personne qui a préparé la clôture ne peut pas l'approuver.
9. L'instantané final est identique à sa relecture (hash inchangé).

**Tests attendus**: spec de chaque étape sur des cas passants et bloquants, spec de clôture complète sur le jeu de référence, spec de reprise après interruption, spec de réouverture et de recalcul, spec des invariants avant et après, spec système de l'assistant.

## 13. P2 · F11 Multi-devises et écarts de change

**Objectif.** Comptabiliser des opérations en devise étrangère dans la devise de la société (EUR par défaut), avec des taux traçables, des écarts de change réalisés calculés au lettrage et des écarts latents traités à la clôture. Cette fonction lève les restrictions posées par F04, F06 et F10 pour les écritures en devise.

### Convention de taux

Une seule convention, appliquée partout: **le taux est le nombre d'unités de devise étrangère pour 1 EUR** (convention de la BCE et d'InforEuro). Montant en EUR = montant en devise ÷ taux. Un test explicite vérifie l'absence d'inversion. Le taux s'enregistre avec 8 décimales.

### Modèle de données

- `currencies`: code ISO 4217, nombre de décimales (0, 2 ou 3 selon la devise).
- `exchange_rates` (déjà prévue au §11 de la spécification des rapports, étendue ici): devise, date ou mois, taux, type (`daily`, `monthly_average`, `closing`, `manual`), source, importé le. Clé d'unicité (devise, date, type, source).
- Sur `journal_entry_lines`: `currency`, `amount_currency` (signé, `numeric(18,4)`), `exchange_rate` utilisé.
- Sur `accounts`: `currency` (compte tenu en devise fixe, par exemple un compte bancaire en USD) et `revalue_at_closing`.
- Sur `partners`: devise par défaut.
- Paramètres de société: `rate_policy` (taux du jour de la pièce, taux moyen mensuel, ou manuel), `rate_date_basis` (date de pièce ou date comptable), comptes d'écart de change réalisé et latent, seuil de contrôle de taux manuel.

### Sources de taux

- Interface `Rates::Provider` avec trois adaptateurs: import BCE (taux journaliers de référence), import InforEuro (taux mensuels, utile pour les rapports à un bailleur, cf. R11), et fichier CSV manuel.
- Un job planifié charge les taux. **Aucune écriture ne va chercher un taux sur le réseau.** Si le taux d'une date manque, la validation est refusée avec un message qui nomme la devise, la date et l'écran où le saisir; jamais d'usage silencieux du dernier taux connu.
- Un taux saisi à la main exige la permission `rates.override` et un motif. Un écart de plus de 5 % (paramétrable) avec le taux officiel déclenche un avertissement.

### Règles de saisie et de conversion

- Conversion ligne par ligne: montant EUR = arrondi à 2 décimales de (montant en devise ÷ taux). Les décimales de la devise (0 pour JPY, 3 pour BHD) s'appliquent au montant en devise.
- Une écriture doit être équilibrée **en EUR**. Pour une pièce entièrement dans une devise, elle doit aussi l'être dans cette devise. La différence d'arrondi éventuelle (jusqu'à 0,02 € par écriture) est portée par une ligne d'arrondi de conversion automatique sur le compte d'écart prévu.
- Le taux de l'opération est figé sur la ligne à la validation.

### Écarts de change réalisés

- Le lettrage (F04) d'une facture et d'un paiement dans la même devise s'effectue **en devise**: Σ des montants en devise = 0. Il est refusé entre devises différentes.
- La différence entre les montants en EUR des lignes lettrées est comptabilisée dans un écart de change réalisé: charge sur le compte de différences de change en charges financières, ou produit sur celui des produits financiers (comptes 654 et 754 du PCMN par défaut, paramétrables).
- **Exception au principe de brouillon** (§2.4): cette écriture est générée par le lettrage et validée automatiquement. Elle est marquée `system`, datée à la date de la ligne la plus récente, liée au lettrage, et défaite avec lui. Un réglage `fx_realized_as_draft` permet de la garder en brouillon.
- Si la date de l'écart tombe dans une période verrouillée, le lettrage est refusé avec un message explicite.
- Lettrage partiel: l'écart est calculé au prorata du montant lettré.

### Écarts latents et réévaluation de clôture

- L'étape 12 de F10 appelle `Fx::Revalue`, qui recalcule au taux de clôture (type `closing`) les créances, dettes et comptes bancaires en devise, et calcule pour chaque poste l'écart entre la valeur comptable en EUR et la valeur au taux de clôture.
- Le traitement des pertes et des gains latents est paramétrable par société. L'agent propose l'approche prudente (perte latente comptabilisée en charge, gain latent différé en régularisation) et la consigne dans `QUESTIONS.md` pour validation par le comptable. Il n'applique aucun traitement sans cette validation.
- Les écritures de réévaluation sont générées en **brouillon**, avec extourne planifiée le premier jour de la période suivante (`auto_reverse_on`, F07).

### Impacts sur les rapports

- R01: soldes en EUR; colonnes optionnelles « Devise » et « Solde en devise » pour les comptes tenus en devise.
- R02: colonnes Devise, Montant en devise et Taux.
- R04: regroupement par devise, équivalent en EUR à la date d'arrêté, option « au taux de clôture ».
- R06: rapprochement dans la devise du compte bancaire; écart de change signalé séparément.
- R11: la conversion mensuelle utilise `exchange_rates` de type `monthly_average` ou `manual`.
- Nouveau rapport **Réévaluation**: liste des postes en devise, taux de clôture, valeur comptable, valeur réévaluée, écart, avec drill-down vers R02.

### Interface

- Sélecteur de devise à la saisie avec le taux et l'équivalent EUR affichés en direct; modification du taux réservée aux droits `rates.override`.
- Écran « Taux de change »: tableau par devise, import, saisie manuelle, alertes de taux manquants pour les 30 prochains jours de saisie.
- Compte bancaire en devise: relevé et rapprochement affichés dans la devise du compte.

### Cas limites

- Facture en USD et paiement en EUR: refusé au lettrage; une écriture de conversion explicite est proposée.
- Note de crédit dans une autre devise que la facture: lettrage refusé.
- Taux à zéro ou négatif: refusé à l'import et à la saisie.
- Devise dont le nombre de décimales change (redénomination): conservé par date d'effet, hors périmètre ici, documenté.
- Écriture datée un jour sans taux publié (week-end): la règle de repli, paramétrable, prend le dernier taux publié **si et seulement si** l'utilisateur l'a activée pour cette devise.

### Critères d'acceptation

1. Une facture de 1 000 USD au taux 1,10 vaut 909,09 EUR; l'écriture est équilibrée en EUR et en USD.
2. Un paiement de 1 000 USD à un autre taux, lettré avec la facture, produit l'écart de change exact, du bon côté, et le lettrage se solde en devise.
3. Défaire le lettrage supprime l'écart de change généré et restaure les résiduels en devise et en EUR.
4. Un taux manquant refuse la validation avec un message qui nomme la devise et la date.
5. La réévaluation génère des brouillons d'écritures avec extourne planifiée au premier jour de la période suivante; sur une devise sans écart, elle ne génère rien.
6. Le taux est bien « devise pour 1 EUR »: un test échoue si la conversion est inversée.
7. Un lettrage entre deux devises différentes est refusé.
8. Les invariants I1 à I11 restent verts sur un jeu de référence enrichi d'opérations en USD et en ZMW.

**Tests attendus**: specs de conversion et d'arrondi sur un tableau de devises à 0, 2 et 3 décimales, spec des écarts réalisés (total, partiel, période verrouillée), spec de `Fx::Revalue`, spec des adaptateurs de taux avec stub HTTP, spec d'invariants sur le jeu enrichi, spec système de la saisie en devise.

## 14. P3 · F12 Multi-dossiers et consolidation

Deux besoins distincts se rejoignent ici: **piloter plusieurs dossiers** (un cabinet, ou un utilisateur qui gère plusieurs sociétés) et **consolider un groupe**. Le premier n'agrège aucune donnée comptable. Le second le fait, sous contrôle strict.

### F12a Espace multi-dossiers

**Objectif.** Voir en un écran l'état de tous les dossiers, sans jamais mélanger leurs données.

**Modèle de données**

- `organizations` (cabinet ou groupe) qui regroupent des `companies`, avec des `organization_memberships` (utilisateur, rôle d'organisation).
- `dossier_health_snapshots`: par société et par jour, calculés par un job à partir des services existants, jamais par une requête qui traverse plusieurs sociétés.

**Tableau de bord du portefeuille**, une ligne par dossier:

- Statut de clôture de l'exercice (F10) et prochaine échéance TVA (R09, F01).
- Anomalies bloquantes et avertissements de R19.
- Lignes bancaires non rapprochées et ancienneté de la plus ancienne (F02).
- Factures Peppol en attente ou en anomalie (F06), documents en boîte de réception (F03).
- Tâches en retard (F08), encours échu clients (R04).
- Date de la dernière écriture validée.

**Fonctionnement**

- Sélecteur de dossier persistant, changement en un clic, dernier dossier mémorisé.
- Tri et filtres par statut, échéance, gravité et responsable de dossier.
- Actions groupées limitées à des actions **sans écriture comptable**: lancer R19, planifier un export, envoyer une notification.
- Chaque instantané n'est visible que par les utilisateurs qui ont accès au dossier concerné. Un utilisateur d'organisation qui n'a accès qu'à certains dossiers ne voit que ceux-là.
- Le tableau de bord se rafraîchit chaque nuit et à la demande, avec la date du dernier calcul visible.

### F12b Consolidation de groupe

**Objectif.** Produire un bilan et un compte de résultat consolidés pour un groupe de sociétés, avec éliminations traçables et rapprochement des opérations intragroupe.

**Avertissement pour l'agent.** Les règles de consolidation belges (seuils, périmètre, méthodes, écarts d'acquisition, conversion) sont techniques. Cette section fixe l'architecture et les mécanismes de contrôle. Chaque choix comptable est écrit dans `QUESTIONS.md` et validé par un comptable avant d'être figé. La première livraison couvre **l'intégration globale** avec intérêts minoritaires, et la **mise en équivalence** simple. L'intégration proportionnelle est hors périmètre.

**Modèle de données**

- `consolidation_groups`: société mère, exercice et date d'arrêté, devise de consolidation.
- `consolidation_members`: société, pourcentage de détention, méthode (`full`, `equity`), date d'entrée et de sortie du périmètre.
- `consolidation_mappings`: rubrique de chaque société (via le moteur de rubriques de R07 et R08) vers une rubrique consolidée.
- `consolidation_runs`: groupe, date d'arrêté, statut (brouillon, validée, figée), auteur, instantané JSON et son empreinte SHA-256.
- `consolidation_entries` et `consolidation_entry_lines`: écritures de consolidation (éliminations et ajustements) avec type, commentaire et justificatif lié (F03). Elles restent **séparées** de la comptabilité de chaque société et ne modifient jamais un grand livre.
- Sur `partners`: `intercompany_company_id` pour marquer un tiers qui est une société du groupe.

**Fonctionnement**

1. **Collecte**: pour chaque membre, la consolidation appelle les services de R07 et R08 avec la date d'arrêté, dans le scope de cette société. Elle n'écrit aucune requête SQL qui traverse plusieurs sociétés.
2. **Conversion** des filiales en devise étrangère (F11): bilan au taux de clôture, compte de résultat au taux moyen, écart de conversion présenté en capitaux propres. Le traitement exact est validé avant d'être figé.
3. **Cumul** des rubriques mappées, société par société.
4. **Éliminations**:
   - Créances et dettes intragroupe: détectées par les tiers marqués `intercompany_company_id`, proposées en écritures d'élimination.
   - Ventes et achats intragroupe: idem, sur les comptes de produits et de charges des tiers marqués.
   - Dividendes intragroupe et élimination des titres de participation contre les capitaux propres de la filiale (écart de première consolidation): écritures **guidées manuelles**, avec justificatif obligatoire.
5. **Intérêts minoritaires**: part des tiers dans les capitaux propres et le résultat des filiales consolidées globalement, calculée d'après le pourcentage de détention.
6. **États consolidés**: bilan, compte de résultat, contribution par société, détail des éliminations, avec comparatif.

**Rapprochement intragroupe.** Un rapport dédié compare, pour chaque paire de sociétés, le montant que chacune déclare (créance chez A, dette chez B). Toute différence est affichée et doit être justifiée par une écriture d'ajustement avant validation du groupe.

**Règles de cohérence**

- Toutes les sociétés du périmètre sont arrêtées à la même date. Si un exercice diffère, la situation intermédiaire de R07 à la date d'arrêté est utilisée, avec un avertissement.
- Chaque écriture de consolidation est équilibrée. Le bilan consolidé est équilibré à chaque étape (cumul, chaque élimination, intérêts minoritaires).
- Un utilisateur doit avoir accès à **tous** les membres pour lancer ou consulter une consolidation. À défaut, elle est refusée, jamais partielle.
- Un run `figé` est immuable: une nouvelle consolidation crée un nouveau run et affiche les différences avec le précédent.

**Interface**

- Assistant de consolidation en étapes: périmètre, collecte, conversion, éliminations, intérêts minoritaires, revue, figer.
- Écran de rapprochement intragroupe avec proposition d'écriture d'ajustement en un clic.
- Exports XLSX et PDF avec le détail des éliminations, le périmètre et l'empreinte de l'instantané.

**Permissions**: `consolidation.view`, `consolidation.run`, `consolidation.approve`, plus l'accès à chaque société membre.

**Cas limites**

- Filiale sortie du groupe en cours d'exercice: prise en compte du prorata de période, avec avertissement.
- Pourcentage de détention qui change: historique conservé par date d'effet.
- Société membre dont un exercice est encore ouvert: consolidation possible à titre provisoire, marquée comme telle sur tous les exports.
- Opération intragroupe non détectée car le tiers n'est pas marqué: listée dans un panneau « tiers proches d'une société du groupe » (même numéro de TVA ou même IBAN).

### Critères d'acceptation

1. Le tableau de bord multi-dossiers n'affiche que les dossiers accessibles, et aucune donnée d'un dossier n'apparaît sous un autre (test avec trois sociétés et deux utilisateurs).
2. Aucune requête de F12 ne lit les tables d'écritures de plusieurs sociétés à la fois (test qui inspecte les requêtes émises).
3. Sur un groupe test (mère à 100 %, filiale à 80 %), avec un prêt intragroupe et une vente intragroupe, les créances et dettes, puis les ventes et achats intragroupe, sont éliminées.
4. Les intérêts minoritaires égalent 20 % des capitaux propres et du résultat de la filiale.
5. Le bilan consolidé est équilibré à chaque étape.
6. Un écart de 200 € entre la créance de A et la dette de B est signalé et bloque la validation du groupe tant qu'aucun ajustement n'est enregistré.
7. Un utilisateur qui n'a pas accès à toutes les sociétés du périmètre ne peut pas lancer la consolidation.
8. Un run figé est identique à sa relecture (hash inchangé), et un nouveau run affiche ses différences avec le précédent.

**Tests attendus**: spec de sécurité et d'isolation (trois sociétés, plusieurs utilisateurs), spec d'inspection des requêtes, spec de cumul et d'élimination sur un groupe de référence à quatre sociétés dont une en devise, spec des intérêts minoritaires, spec de rapprochement intragroupe, spec d'immuabilité des runs.

## 15. P3 · F13 Import, export et API

**Objectif.** Faire entrer et sortir des données de LedgerFlow de façon sûre, versionnée et documentée: imports guidés depuis Excel et CSV, exports de données complets, et une API REST publique avec webhooks. La migration complète d'un dossier reste l'objet de F05; cette fonction couvre les échanges courants.

### F13a Imports guidés

**Données concernées**: tiers, plan comptable, écritures en lot (journal de paie, ventes d'une boutique en ligne, écritures d'un autre outil), et éventuellement budgets.

**Parcours**

1. **Dépôt** d'un fichier CSV ou XLSX (encodage et séparateur détectés).
2. **Mapping** des colonnes vers les champs, enregistrable comme modèle (`import_templates`) réutilisable au prochain import.
3. **Prévisualisation** avec validation ligne par ligne: erreurs bloquantes, avertissements, comptage.
4. **Simulation** (dry-run) qui n'écrit rien.
5. **Import** en lot, avec un identifiant de lot (`import_batch_id`) porté par chaque objet créé.

**Règles**

- Les écritures importées passent par `Ledger::PostEntry` et sont créées en **brouillon**. Les lignes sont regroupées en pièces par une clé (numéro de pièce). Une pièce déséquilibrée est refusée en entier, listée avec sa cause, et n'empêche pas l'import des autres.
- **Idempotence**: une clé externe (`external_id`) ou l'empreinte du fichier évite tout doublon en cas de relance.
- Comptes, tiers et codes TVA inconnus ne sont jamais créés en silence: le mapping propose de les relier ou de les créer avec confirmation.
- Un lot se défait tant qu'il ne contient que des brouillons (suppression du lot); s'il a été validé, l'annulation passe par une extourne du lot avec motif (F07).
- Limite de taille configurable, traitement en tâche de fond au-delà de 5 000 lignes, avec barre de progression.

### F13b Exports de données

- **Export standard**: plan comptable, tiers, journaux, écritures avec leurs lignes, par période, en CSV, XLSX et JSON à plat. Chaque fichier porte un `schema_version` et un dictionnaire de colonnes est publié dans `docs/exports.md`.
- **Sauvegarde complète du dossier** (portabilité): archive ZIP contenant toutes les données, les pièces de F03, le journal d'audit et un manifeste avec le hash SHA-256 de chaque fichier. Réservée à un propriétaire, journalisée, lien signé à durée limitée.
- Les gros exports sont traités en flux ou en tâche de fond, sans charger toutes les lignes en mémoire.
- Permission `exports.data`. Chaque export est tracé dans l'audit (qui, quoi, quelles données, quel format).

### F13c API REST publique

**Principes**

- Version `/api/v1`, spécification **OpenAPI 3.1** générée à partir des tests (rswag) et servie à `/api/docs`.
- Authentification par JWT (existant) et par **jetons d'accès personnels** avec portées, expiration et rotation. Seul le hash du jeton est stocké; le jeton s'affiche une seule fois. La date du dernier usage est visible. Les portées ne dépassent jamais les permissions du propriétaire (F01).
- Limitation de débit par jeton (défaut 60 requêtes par minute, `Rack::Attack`), avec en-têtes explicites.
- Pagination par curseur, filtres et tris homogènes, erreurs au format `application/problem+json` (RFC 9457).
- Concurrence optimiste: `ETag` et `If-Match` sur les mises à jour.
- En-tête `Idempotency-Key` accepté sur tous les `POST` qui créent des données: rejouer la requête renvoie la même réponse sans doublon.
- Scope de société porté par le jeton; un jeton d'organisation doit désigner explicitement une société parmi celles qu'il peut voir.

**Ressources exposées**: comptes, tiers, journaux, écritures et lignes, documents, relevés et lignes bancaires, tâches, périodes et verrous, rapports (le `Reports::Result` en JSON), lettrages.

**Règles d'écriture**

- L'API passe par les mêmes services (`Ledger::PostEntry`, `Ledger::ReverseEntry`, `Ledger::Reconcile`) et les mêmes policies que l'interface. Elle ne contourne rien.
- Création d'écritures: **brouillon** par défaut. La validation est une action explicite (`POST /entries/:id/post`) qui exige `entries.post`.
- Une écriture validée ne se modifie pas par l'API: on l'extourne.

**Webhooks sortants**

- Événements: `entry.posted`, `entry.reversed`, `reconciliation.created`, `period.locked`, `document.created`, `peppol.received`, `closing.completed`.
- Signature HMAC dans un en-tête, secret par abonnement avec rotation, tentatives avec attente croissante, journal des livraisons consultable et bouton de rejeu.
- Charge utile versionnée (`payload_version`), sans données sensibles superflues.

### Sécurité et audit

Création, rotation et révocation de jetons, imports, exports, création d'abonnements webhook et tous les appels d'écriture par API sont journalisés. Les jetons, secrets et IBAN sont masqués dans les journaux applicatifs.

### Cas limites

- Fichier importé avec dates à formats mixtes: refusé avec les lignes en cause plutôt que deviné.
- Import d'une pièce dans une période verrouillée: refusé par F01, avec le message correspondant.
- Jeton révoqué pendant une requête longue: la requête suivante est refusée.
- Webhook dont la destination est indisponible plusieurs jours: abonnement suspendu après un nombre d'échecs paramétrable, notification aux propriétaires.
- Deux requêtes API simultanées sur la même ressource: la seconde reçoit `412 Precondition Failed` si son `ETag` est périmé.

### Critères d'acceptation

1. Un import de 1 000 lignes avec 3 pièces déséquilibrées crée toutes les pièces valides en brouillon et liste les 3 refusées avec leur cause.
2. Relancer le même import ne crée aucun doublon.
3. Le retour arrière d'un lot de brouillons ne supprime rien d'autre que ce lot.
4. Un jeton dont la portée dépasse les droits de son propriétaire est refusé à la création.
5. Rejouer un `POST` avec la même `Idempotency-Key` renvoie la même réponse et ne crée rien de plus.
6. Une écriture créée par API est en brouillon; sa validation par API sans `entries.post` est refusée avec `403`.
7. Un webhook signé est vérifiable avec le secret; une signature falsifiée est rejetée par le récepteur de test, et un échec est rejoué selon la politique.
8. La spécification OpenAPI générée est valide, et un test de compatibilité échoue si une modification casse la version `v1`.
9. La sauvegarde complète se décompresse et son manifeste vérifie chaque hash.

**Tests attendus**: specs d'import (mapping, prévisualisation, simulation, pièces déséquilibrées, idempotence), spec des exports en flux, specs d'API par ressource avec rswag, specs d'authentification, de portées et de limitation de débit, spec d'idempotence et de concurrence, spec de webhook avec récepteur de test, test de compatibilité OpenAPI en CI.

## 16. Stratégie de tests et définition de « terminé »

Ces fonctions écrivent dans le grand livre et gèrent des droits. Le risque principal n'est pas un écran cassé, mais une écriture fausse, un droit contourné ou un doublon silencieux. La stratégie vise donc d'abord ces trois risques.

### Jeu de données de référence enrichi

On reprend le jeu du §15 de la spécification des rapports et on lui ajoute, fonction par fonction:

| Fonction | Ajouts au jeu de référence |
| --- | --- |
| F01 | Cinq utilisateurs (un par rôle) et deux sociétés, dont un utilisateur présent dans les deux avec des rôles différents |
| F02 | Trois fichiers CODA anonymisés de deux banques: paiement groupé, paiement partiel, communication structurée, frais sans contrepartie, virement interne, recoupement de relevés, fichier corrompu |
| F03 | Trente pièces: PDF avec texte, scan, XML UBL, archive ZIP, doublon exact, doublon probable, PDF protégé, fichier au type falsifié |
| F04 | Paires exactes, groupe équilibré, combinaison de plusieurs lignes contre une, écart d'arrondi, note de crédit |
| F05 | Dossier WinBooks anonymisé fourni par l'utilisateur, et dossier synthétique de 5 000 lignes avec anomalies volontaires |
| F06 | Exemples officiels Peppol BIS Billing 3.0 (facture, note de crédit, remises, autoliquidation) et messages falsifiés |
| F07 | Modèles, loyer récurrent avec indexation, échéances manquées, extournes de cas particuliers |
| F08, F09 | Tâches, litiges, promesses de paiement, historique de trois niveaux de relance |
| F10 | Clôture complète du jeu de référence, avec étapes manuelles simulées |
| F11 | Opérations en USD et en ZMW avec taux quotidiens et mensuels, écarts réalisés et latents |
| F12 | Groupe de quatre sociétés dont une en devise, avec prêt et ventes intragroupe |
| F13 | Fichiers d'import CSV et XLSX (avec erreurs), jetons d'API de portées différentes, récepteur de webhook de test |

Comme pour les rapports, les résultats attendus sont **calculés indépendamment** du code testé (tableur ou SQL brut) et figés dans `spec/fixtures/reference_ledger/expected/`.

### Niveaux de tests

- **Services d'écriture**: specs sur tableaux de cas pour `Ledger::PostEntry`, `ReverseEntry`, `Reconcile`, `Unreconcile`, `Fx::Revalue`.
- **Séquences aléatoires**: un test génère des suites d'opérations (saisir, valider, extourner, lettrer, délettrer, verrouiller, déverrouiller, importer, générer une récurrente) et vérifie après chaque suite que les invariants I1 à I11 tiennent. Graine journalisée pour rejouer un échec.
- **Droits**: une matrice unique `Permissions::MATRIX` (rôle × action → autorisé ou refusé) alimente à la fois l'interface et les tests. Un test parcourt toute la matrice, par l'interface **et** par l'API.
- **Isolation entre sociétés**: exemple partagé `it_behaves_like "company scoped"` appliqué à chaque endpoint et à chaque job.
- **Concurrence**: lettrage simultané, import simultané du même fichier, deux instances du job de récurrence, déverrouillage pendant une validation. Un seul gagnant, aucun doublon.
- **Fichiers hostiles**: type MIME falsifié, archive ZIP piégée, PDF corrompu, XML avec entités externes. Le traitement doit échouer proprement et ne rien exécuter.
- **Intégrations**: Digiteal, sources de taux et envoi d'e-mail sont simulés par des stubs HTTP, y compris les erreurs, les délais et les réponses incohérentes.
- **Parcours système** (Capybara): import CODA → rapprochement → lettrage → déclaration TVA → clôture → réouverture, avec vérification des invariants à chaque étape.
- **Performance** (tag `:perf`, exécuté chaque nuit): import CODA de 10 000 lignes en moins de 60 s; suggestions de lettrage sur 5 000 tiers en moins de 30 s; migration de 500 000 lignes en moins de dix minutes; listes d'API de 100 éléments en moins de 300 ms au 95e centile.
- **Mutation** (Mutant): sur les services d'écriture, le moteur de scoring du rapprochement, la matrice de droits et la conversion de devises.
- **Qualité et sécurité**: RuboCop, Brakeman, Bullet, `bundler-audit`, `i18n-tasks` (fr, nl, en), contrôle d'accessibilité, détection de secrets dans le dépôt.
- **Migrations de schéma**: chaque migration est testée en montée et en descente sur une copie de la base de référence.

### Activation progressive

Chaque fonction est livrée derrière un **drapeau par société** (`feature_f01` à `feature_f13`, par exemple avec Flipper). Un propriétaire ou l'administrateur de la plateforme l'active. Un drapeau désactivé masque l'interface et l'API de la fonction, sans effet sur les données existantes. Cela permet de la valider sur un dossier pilote avant de l'ouvrir aux autres.

### Définition de « terminé » pour chaque fonction

- [ ] Tous les tests de la fonction passent; couverture SimpleCov d'au moins 95 % sur son dossier `app/features/<nom>/`.
- [ ] Score de mutation d'au moins 85 % sur ses services d'écriture et sa logique de décision.
- [ ] Les invariants I1 à I11 sont verts, y compris après une séquence aléatoire d'opérations.
- [ ] Chaque action est couverte par la matrice de droits et testée par l'interface et par l'API.
- [ ] L'isolation entre sociétés est testée sur chaque endpoint et chaque job.
- [ ] Idempotence et concurrence testées pour tout import, job ou traitement de fond.
- [ ] Aucune écriture validée n'est créée sans action humaine, sauf les exceptions listées dans la section de la fonction.
- [ ] Toute action de la fonction est journalisée dans l'audit, avec l'auteur et le motif si requis.
- [ ] Budgets de performance tenus.
- [ ] Libellés en fr, nl et en; états vides, chargement et erreurs traités.
- [ ] Fonction livrée derrière son drapeau de société et documentée dans `docs/features/Fxx.md` (usage, règles, limites).
- [ ] Le compte rendu de l'agent liste ses hypothèses, ses écarts avec cette spécification et les questions à valider par un comptable dans `QUESTIONS.md`.

## 17. Prompts prêts à l'emploi pour Claude Code

Enregistrez ce document dans le dépôt sous `docs/features/SPEC.md`, à côté de `docs/reports/SPEC.md`. Les prompts s'y réfèrent par leurs numéros de section. Donnez-les un par un, dans l'ordre, et validez le résultat de chacun avant de passer au suivant.

### 17.1 Règles permanentes (à ajouter à `CLAUDE.md`)

```text
Fonctions transverses — règles de travail
- Les sources de vérité sont docs/features/SPEC.md et docs/reports/SPEC.md. En cas de doute, les relire; ne pas deviner.
- TDD strict: test rouge, code minimal, test vert, refactoring. Un commit par étape cohérente.
- Une fonction à la fois. Ne pas commencer la suivante tant que la définition de « terminé » (§16) n'est pas remplie.
- Toute écriture comptable passe par Ledger::PostEntry, ReverseEntry, Reconcile ou Unreconcile. Aucun autre code n'écrit dans journal_entries ni journal_entry_lines, ni ne modifie amount_residual.
- Aucun traitement automatique ne valide une écriture, sauf les exceptions listées explicitement dans la section de la fonction.
- Chaque action est autorisée par une policy côté serveur, testée par l'interface et par l'API, et journalisée dans l'audit.
- Tout import, job et traitement de fond est idempotent et testé pour la concurrence.
- Chaque fonction est livrée derrière un drapeau de société (feature_fxx).
- Montants en numeric(15,2) en base, BigDecimal en Ruby, jamais Float. Toutes les migrations sont réversibles.
- Ne jamais modifier BudgetFlow ni l'intégration Digiteal existante sans accord explicite.
- Si une règle comptable, fiscale ou légale manque ou paraît douteuse, appliquer le comportement le plus prudent, l'inscrire dans docs/features/QUESTIONS.md avec sa justification, et continuer.
- Ne jamais supprimer ou affaiblir un test pour le faire passer.
```

### 17.2 Prompt d'audit (à donner en premier, sans coder)

```text
Lis intégralement docs/features/SPEC.md et docs/reports/SPEC.md. Ne modifie aucun fichier de code.

Audite ensuite le dépôt et produis docs/features/00-audit.md contenant:
1. Pour chaque fonction F01 à F13: ce qui existe déjà (modèles, services, écrans, tests), ce qui manque, et les migrations nécessaires avec leur risque.
2. L'état réel des services d'écriture comptable, du lettrage, du verrouillage de périodes, de l'audit, du stockage de fichiers et de l'authentification. Signale tout endroit où du code écrit directement dans les écritures sans passer par un service.
3. L'état de l'intégration Peppol via Digiteal (F06) et de l'API JWT (F13).
4. Les dépendances entre fonctions qui te semblent différentes de celles du §3.
5. Les points du SPEC ambigus, contradictoires ou incompatibles avec le code existant.
6. Un plan détaillé de la vague P0, tâche par tâche, avec l'ordre des commits.

Arrête-toi après avoir écrit ce fichier et attends ma validation.
```

### 17.3 Prompt générique d'une fonction

```text
Implémente la fonction Fxx décrite dans la section §N de docs/features/SPEC.md, en suivant docs/features/00-audit.md.

Procède en TDD dans cet ordre:
1. Les jeux de données de référence et les résultats attendus indépendants de la fonction (§16).
2. Les specs des services et des policies, y compris tous les cas limites et la concurrence.
3. Les migrations réversibles, les modèles, les services LightService et les jobs.
4. Le contrôleur, l'endpoint API, les composants et les écrans.
5. La matrice de droits, l'isolation entre sociétés, l'audit et le drapeau feature_fxx.
6. Les invariants I1 à I11, y compris par séquences aléatoires quand la fonction écrit dans le grand livre.
7. Les traductions fr, nl, en et docs/features/Fxx.md.

Vérifie chaque critère d'acceptation de la section un par un, en citant le test qui le couvre. Ne passe pas à la fonction suivante. Termine par un compte rendu: critères couverts, écarts avec le SPEC, questions ajoutées à QUESTIONS.md.
```

### 17.4 Prompts par vague

**P0**

```text
Implémente dans cet ordre, en appliquant le prompt générique 17.3 à chacun: F01 (§4), puis F03 (§6), puis F02 (§5). Après chaque fonction, arrête-toi et présente le compte rendu. À la fin de la vague, vérifie les critères de sortie de P0 du §3 et exécute le parcours système: import CODA, rapprochement, période verrouillée, pièce consultable depuis une écriture.
```

**P1**

```text
Implémente F04 (§7), puis F05 (§8), puis F06 (§9), puis F07 (§10). Pour F05, commence par analyser le dossier WinBooks fourni et documente ce que tu observes; n'invente aucun nom de table ou de colonne. Pour F06, commence par l'audit de l'intégration Digiteal existante (docs/features/F06-audit.md) et attends ma validation avant de modifier le code. Vérifie les critères de sortie de P1 du §3.
```

**P2**

```text
Implémente F08 et F09 (§11), puis F11 (§13), puis F10 (§12). F11 précède F10 parce que l'étape 12 de la clôture dépend de la réévaluation des devises. Pour F09, aucun taux d'intérêt de retard n'est codé en dur. Pour F11 et F10, chaque choix de traitement comptable non tranché par le SPEC est écrit dans QUESTIONS.md. Vérifie les critères de sortie de P2 du §3.
```

**P3**

```text
Implémente F13 (§15), puis F12 (§14). Pour F12b, commence par l'architecture et les mécanismes de contrôle, et n'applique aucune règle de consolidation sans validation d'un comptable consignée dans QUESTIONS.md. Vérifie les critères de sortie de P3 du §3.
```

### 17.5 Prompt de revue de fin de vague

```text
Fais une revue critique de la vague P<n>, comme le ferait un expert-comptable et un auditeur de sécurité qui n'ont pas vu le code.

1. Relis les sections du SPEC de la vague et compare-les au code livré, critère par critère.
2. Exécute la suite complète, les séquences aléatoires d'invariants, les tests de concurrence et les tests de performance.
3. Cherche activement: une écriture créée sans passer par les services, une action sans policy ou sans audit, une requête sans scope de société, un import ou un job non idempotent, un fichier traité sans contrôle de type.
4. Vérifie que rien n'est validé automatiquement en dehors des exceptions listées.
5. Liste tout écart, même mineur, avec le fichier, la ligne et le test qui manque.

Ne corrige rien tant que je n'ai pas validé la liste.
```

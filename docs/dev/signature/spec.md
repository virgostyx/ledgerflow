# Spécification des fonctions signature – LedgerFlow

Sep 26, 2026 · @Virgo STYX

## 1. Contexte, objectifs et principes

Ce document décrit trois fonctions signature de LedgerFlow, celles qui donnent au logiciel une identité propre: les **paiements fournisseurs** de bout en bout (B01), la **traçabilité temporelle avec certificat d'intégrité** (B03) et le **portail client** (B02). Elles se déclinent en neuf capacités, classées en trois vagues (P0 à P2). Il complète la spécification des rapports (`docs/reports/SPEC.md`), celle des fonctions transverses (`docs/features/SPEC.md`) et celle de l'agent IA (`docs/agent/SPEC.md`), dont il réutilise les services, les droits, l'audit et la définition de « terminé ».

Il est écrit pour être donné tel quel à un agent de codage (Claude Code): lecture complète, audit du dépôt, puis implémentation capacité par capacité (voir §14).

### Pourquoi ces trois axes

| Axe | Ce qu'il apporte | Pourquoi il distingue LedgerFlow |
| --- | --- | --- |
| **B01 Paiements fournisseurs** | Facture reçue, bon à payer, lot de paiement SEPA, confirmation par la banque, rapprochement automatique | C'est la tâche hebdomadaire de tout comptable, et la moitié se passe souvent hors du logiciel. Les contrôles anti-fraude sur les coordonnées bancaires en font aussi un argument de confiance |
| **B03 Traçabilité temporelle** | Voir la comptabilité telle qu'elle était à un moment donné, savoir ce qui a changé, et prouver l'intégrité par un certificat vérifiable hors de l'application | Peu de logiciels le font. L'architecture d'audit chaîné et les instantanés figés existent déjà; il s'agit de les rendre visibles et démontrables |
| **B02 Portail client** | Dépôt de pièces, questions, validation des comptes, tableau de bord | Sort les échanges des e-mails et donne au client une raison de rester. C'est aussi la plus grande surface d'exposition, d'où son rang en dernier |

### Principes directeurs

Ces principes commandent toutes les décisions de conception. En cas de conflit entre une commodité et un principe, le principe l'emporte.

1. **LedgerFlow ne détient aucun moyen de paiement.** Aucun identifiant bancaire de l'utilisateur, aucune initiation de paiement. Le logiciel prépare un fichier que l'humain charge et **autorise dans sa propre banque**.
2. **Séparation des tâches.** Celui qui saisit, celui qui approuve et celui qui autorise le paiement sont trois personnes distinctes par défaut. Toute dérogation est un réglage explicite d'un propriétaire, journalisé.
3. **Rien d'irréversible sans contrôle ni trace.** États explicites, fichiers exportés immuables, correction par extourne plutôt que par modification.
4. **Le passé se reconstruit, il ne se réécrit pas.** Toute vue historique est dérivée des données et du journal d'audit, jamais d'une copie modifiable, et elle est validée par des témoins indépendants (instantanés figés).
5. **La preuve se vérifie hors de l'application.** Empreintes, chaînes de hachage et signatures publiques permettent à un tiers de contrôler sans avoir accès à LedgerFlow.
6. **Le portail publie, il n'expose pas.** Un externe ne lit jamais le grand livre en direct. Il voit des **publications** explicites, choisies par le cabinet, et il dépose ou répond.
7. **Rien de ce qui vient d'un externe n'est fiable.** Pièces, réponses et messages du portail sont traités comme des documents reçus: contrôlés, isolés, jamais exécutés ni validés automatiquement.
8. **Réseaux imparfaits.** Les envois de pièces reprennent après coupure et se mettent en file hors ligne.
9. **Mesurable.** Chaque capacité définit ses indicateurs (délai d'approbation, taux de paiements rapprochés automatiquement, délai de réponse d'un client).

### Hypothèses de travail (à corriger si elles sont fausses)

- Application Ruby on Rails avec PostgreSQL, ViewComponent, Stimulus, Tailwind, LightService, RSpec, développée en TDD, avec l'API REST JWT et l'authentification multi-modèles existantes.
- Cadre belge et zone SEPA: paiements en EUR, relevés CODA, TVA belge, plan comptable PCMN.
- Utilisateurs: cabinets comptables et sociétés, en français, néerlandais et anglais.
- Les rapports R01 à R20 et les fonctions F01 à F13 sont implémentés ou en cours. Ces capacités dépendent surtout de F01 (droits), F02 (CODA), F03 (pièces), F06 (Peppol), F08 (tâches), R18 (audit) et R19 (contrôles).
- Si un client mobile d'approbation existe déjà (par exemple comme projet séparé), l'audit du §14 évalue sa réutilisation avant tout développement.

**Gabarit de chaque capacité**: Objectif · Modèle de données · Règles · Interface · Cas limites · Sécurité · Critères d'acceptation · Tests.

**Hors périmètre**: initiation de paiement par API bancaire (PSD2), paiements hors zone SEPA, prélèvements SEPA (domiciliations), signature électronique qualifiée, application mobile native, comptabilité de paie.

## 2. Principes transverses et liens avec les spécifications précédentes

Ces capacités ne repartent pas de zéro: elles **assemblent** des briques déjà spécifiées. Les règles générales des trois documents précédents (services d'écriture, idempotence, audit, montants en `numeric(15,2)`, brouillon par défaut, drapeaux de société, définition de « terminé ») s'appliquent sans exception. Cette section ne rappelle que ce qui est propre à ces trois axes.

### 2.1 Ce qui est réutilisé

| Besoin | Brique existante |
| --- | --- |
| Droits, périodes verrouillées, quatre yeux, second facteur | F01 (`Permissions::MATRIX`, `period_locks`) |
| Factures reçues et propositions d'écriture | F06 (Peppol), F03 et A09 (documents), A07 (propositions) |
| Relevés bancaires et rapprochement | F02 (CODA), R06, F04 (lettrage) |
| Création, extourne et lettrage d'écritures | `Ledger::PostEntry`, `Ledger::ReverseEntry`, `Ledger::Reconcile` |
| Journal d'audit chaîné et intégrité des pièces | R18, `audit:verify`, `documents:verify` |
| Tâches, commentaires, notifications | F08 |
| Tableaux, graphiques, exports | `Reports::Result`, `Reports::Filters`, `Reports::ChartComponent`, exporteurs |
| Instantanés figés (témoins de vérité) | Clôture F10, TVA déposée R09, rapprochements figés R06, `consolidation_runs` F12 |

### 2.2 Nouvelles permissions

La matrice de F01 reçoit ces lignes. Les capacités d'approbation sont en plus soumises aux politiques de §4: avoir la permission ne suffit pas, il faut être désigné comme approbateur.

| Capacité | Propriétaire | Comptable | Assistant | Lecteur | Auditeur externe |
| --- | --- | --- | --- | --- | --- |
| `approvals.approve` (donner un bon à payer) | Oui | Oui | Non | Non | Non |
| `approvals.configure` (politiques et délégations) | Oui | Non | Non | Non | Non |
| `payments.prepare` (composer un lot) | Oui | Oui | Oui | Non | Non |
| `payments.approve` (autoriser un lot) | Oui | Oui, selon seuils | Non | Non | Non |
| `payments.export` (générer le fichier, second facteur exigé) | Oui | Oui | Non | Non | Non |
| `payments.confirm` (marquer comme soumis, valider les paiements) | Oui | Oui | Non | Non | Non |
| `bank_accounts.verify` (vérifier un IBAN de tiers) | Oui | Oui | Non | Non | Non |
| `time_travel.view` (vue historique) | Oui | Oui | Oui | Oui | Oui |
| `integrity.issue` (émettre un certificat) | Oui | Oui | Non | Non | Non |
| `portal.manage` (invitations et droits externes) | Oui | Oui | Non | Non | Non |
| `portal.publish` (publier vers le portail) | Oui | Oui | Non | Non | Non |

`time_travel.view` ne donne jamais plus que les droits de lecture habituels de l'utilisateur: la vue historique applique les mêmes restrictions par journal et par compte que la vue courante.

### 2.3 Invariants ajoutés

Ils s'ajoutent à I1 à I11 et sont exécutés dans les mêmes tests et par R19.

| ID | Invariant | Vérifié par |
| --- | --- | --- |
| I12 | Pour tout compte et tous instants T1 < T2, la variation de solde connue entre T1 et T2 égale la somme des lignes validées postées entre T1 et T2, à date d'arrêté constante | B03a, B03b |
| I13 | Pour tout lot de paiement: Σ paiements = total du lot = contrôle de somme du fichier; après confirmation, le débit bancaire égale le total des paiements confirmés | B01b, B01c |
| I14 | Une facture n'appartient qu'à un seul lot actif, et aucune facture n'est payée deux fois | B01b |
| I15 | La racine de hachage recalculée à partir des écritures d'un ancrage égale la racine enregistrée, et la chaîne d'ancrages est ininterrompue | B03c |

### 2.4 Lien avec l'agent IA

L'agent reçoit des **outils de lecture supplémentaires** (à ajouter au catalogue d'A02): `list_pending_approvals`, `get_payment_batch`, `get_changes_between` et `get_integrity_status`. Les outils de rapports acceptent un argument optionnel `known_at` (B03a).

L'agent **n'approuve, n'exporte, ne confirme et ne paie jamais**. Il peut expliquer pourquoi une facture est bloquée, résumer les changements depuis la dernière visite (A10) et proposer une tâche (A07). **Il n'est pas exposé au portail client**: le portail ne donne accès à aucune capacité de l'agent.

### 2.5 Conventions communes

- Chaque capacité est livrée derrière un drapeau de société (`feature_b01a`, `feature_b01b`, …).
- Chaque action est autorisée côté serveur par une policy, testée par l'interface et par l'API, et journalisée dans R18 avec l'acteur, l'objet, l'état avant et après, et le motif quand il est exigé.
- Libellés en fr, nl et en; états vides, chargement et erreurs traités; accessibilité vérifiée.
- Toute donnée qui part du serveur vers un externe (portail, e-mail) suit la règle du moindre détail: compteurs et liens plutôt que montants et noms, sauf réglage explicite.

## 3. Feuille de route

Les capacités suivent l'ordre ci-dessous. Une vague n'est terminée que lorsque tous ses critères d'acceptation passent et que les invariants I1 à I15 sont verts; l'agent de codage ne démarre pas la vague suivante avant.

| Ordre | Réf. | Capacité | Vague | Dépend de | Effort |
| --- | --- | --- | --- | --- | --- |
| 1 | B01a | Circuit d'approbation des factures (bon à payer) | P0 | F01, F03, F06, F08 | L |
| 2 | B01b | Lots de paiement SEPA et contrôle des coordonnées bancaires | P0 | B01a, F01, R14 | XL |
| 3 | B01c | Confirmation, rapprochement et retours de paiement | P0 | B01b, F02, F04, F07 | L |
| 4 | B03a | États de la comptabilité à une date de connaissance | P1 | R18, F01, R01 à R09 | L |
| 5 | B03b | Rapport de changements entre deux moments | P1 | B03a | M |
| 6 | B03c | Ancrage, certificat d'intégrité et vérification indépendante | P1 | B03a, R18, F03 | XL |
| 7 | B02a | Portail client: identité, accès et publication | P2 | F01, F03, B03c | XL |
| 8 | B02b | Dépôt de pièces (mobile, réseaux instables) | P2 | B02a, F03 | L |
| 9 | B02c | Questions, validation des comptes et tableau de bord client | P2 | B02a, F08, R13, B03c | L |

Effort relatif avec un agent de codage: S = une session, M = deux à trois, L = quatre à six, XL = plus de six.

**Pourquoi cet ordre.** B01 est autonome et apporte une valeur immédiate à l'usage hebdomadaire. B03 vient ensuite: il renforce la confiance, s'appuie sur l'audit et les instantanés déjà en place, et son certificat sert de preuve dans le portail. B02 passe en dernier parce qu'il ouvre le système à des personnes extérieures: il ne doit arriver que sur des fondations de sécurité, d'audit et de preuve éprouvées.

**Critères de sortie de chaque vague**

- **P0**: aucune facture ne se paie sans avoir franchi son circuit d'approbation; le fichier de paiement n'est généré que pour des factures approuvées et des IBAN vérifiés; il est immuable une fois exporté; sur le jeu de référence, au moins 90 % des lots sont reconnus automatiquement dans le CODA; aucun identifiant bancaire de l'utilisateur n'est stocké; I13 et I14 verts.
- **P1**: la vue historique reproduit à l'euro près les instantanés figés existants (clôture, TVA déposée, rapprochements figés); le rapport de changements satisfait I12; un certificat se vérifie hors ligne avec l'outil indépendant, et une modification volontaire d'une écriture est détectée; I15 vert.
- **P2**: un utilisateur externe ne peut atteindre aucune donnée non publiée (tests d'accès direct à des identifiants sur chaque point d'entrée); le second facteur est obligatoire pour tous; un dépôt de pièces reprend après coupure réseau; toute validation par un client est liée au hash de la publication qu'il a vue.

## 4. P0 · B01a Circuit d'approbation des factures (bon à payer)

**Objectif.** Faire approuver chaque facture d'achat par la bonne personne, au bon niveau, avec une trace irréfutable, avant qu'elle puisse être payée. L'approbateur voit tout ce qu'il lui faut pour décider en une minute, y compris depuis son téléphone.

### Bon à payer et validation comptable sont deux choses

Le **bon à payer** (BAP) confirme que la dépense est justifiée: service rendu, prix correct, budget disponible. La **validation** d'une écriture (`entries.post`) confirme qu'elle est correctement comptabilisée. Les deux sont indépendantes.

Par défaut, le BAP **conditionne le paiement, pas la comptabilisation**. Une facture peut et doit être comptabilisée à temps, car la déduction de TVA ne doit pas dépendre des délais d'approbation. Un réglage `bap_before_posting` permet à une société d'exiger le BAP avant la validation de l'écriture.

### Modèle de données

- `approval_policies`: société, nom, sujet (`purchase_invoice`, `payment_batch`), conditions, étapes, priorité, actif, version.
  - Conditions possibles: plage de montant TTC, fournisseur ou catégorie, journal, compte de charge, projet ou centre analytique (R12), « premier paiement à ce fournisseur », devise.
  - La première politique qui correspond, par ordre de priorité, s'applique.
- `approval_steps`: politique, rang, mode (`any_of`: un seul des approbateurs suffit, `all_of`: tous), approbateurs (utilisateurs ou rôles), délai de service en heures, personne d'escalade.
- `approval_requests`: sujet (écriture d'achat ou lot), version de politique, étape courante, statut (`pending`, `approved`, `rejected`, `changes_requested`, `cancelled`, `invalidated`), **empreinte du contenu** soumis, soumis par, dates.
- `approval_decisions`: demande, étape, approbateur, décision, commentaire, date, canal (web ou mobile), empreinte de l'appareil.
- `approval_delegations`: délégant, délégataire, début, fin, portée (toutes les politiques ou certaines), motif.
- Sur l'écriture d'achat: `payment_status` (`to_approve`, `approved`, `not_required`, `on_hold`, `scheduled`, `paid`, `disputed`).

### Fonctionnement

1. **Soumission**: à la création d'un brouillon d'achat (saisie, Peppol F06, proposition A07) ou par « Soumettre pour approbation ». Le moteur choisit la politique. Sans politique applicable, le BAP est `not_required`, et cela est enregistré.
2. **Circuit**: étapes dans l'ordre, chaque étape en mode `any_of` ou `all_of`. Un refus à n'importe quelle étape arrête le circuit.
3. **Contexte visible pour l'approbateur**: la pièce (visionneuse F03), le codage comptable et la TVA, l'historique du fournisseur (cinq dernières factures et montant moyen, avec un badge quand le montant dépasse deux fois la moyenne), l'état de la ligne de budget si un projet est concerné (R11: consommé et solde), les avertissements de doublon (F03) et de changement d'IBAN (B01b), les commentaires internes (F08).
4. **Décisions possibles**: Approuver; Refuser (motif obligatoire); Demander une modification (crée une tâche F08 pour l'auteur, avec le commentaire); Transférer à un autre approbateur autorisé.
5. **Invalidation**: si le contenu approuvé change sur un champ significatif (fournisseur, montant TTC, lignes et comptes, échéance, IBAN de la facture, pièce), l'approbation est `invalidated` et la demande repart à la première étape, avec la raison. Les champs cosmétiques (libellé libre) ne l'invalident pas.
6. **Approbation obtenue**: `payment_status` passe à `approved`; la facture devient éligible à un lot de paiement (B01b).

### Séparation des tâches

- L'auteur d'une écriture ne peut pas l'approuver.
- Avec le réglage `distinct_payment_authorizer`, celui qui a donné le BAP ne peut pas autoriser le lot qui la contient (B01b).
- Les délégations ne sont **pas transitives**, sont limitées dans le temps, ne permettent pas d'approuver ses propres saisies, et sont visibles de tous les propriétaires.

### Délais, escalade et absence

- Rappels à 24 et 48 heures (paramétrables), puis **escalade** vers la personne prévue à l'expiration du délai de service.
- Approbateur désactivé ou absent: la demande est reroutée vers son remplaçant ou vers un propriétaire, avec alerte.
- Un résumé quotidien des approbations en attente est envoyé à chaque approbateur (compteurs et liens, sans montants ni noms par défaut).

### Interface

- Écran **« À approuver »**: liste triée par échéance de paiement puis par ancienneté, filtres par fournisseur, montant et projet.
- **Approbation groupée** pour les factures sous un seuil (`bulk_threshold`) et sans avertissement; chaque décision reste enregistrée séparément.
- **Mobile**: interface adaptative (application web installable) avec notifications push au texte neutre (« 3 factures à approuver »), lien direct vers l'écran authentifié. Au-delà d'un montant paramétrable (`step_up_threshold`), une nouvelle authentification (second facteur) est demandée avant d'approuver.
- Sur la fiche d'une facture: frise des étapes avec les décisions et les commentaires.
- **Tableau des approbations**: délais moyens, refus, demandes en retard, par approbateur et par fournisseur.

### Autres capacités liées

- R14 (prévisionnel de trésorerie) distingue les sorties **approuvées** des sorties **en attente d'approbation**.
- L'API expose la liste et la décision (`/api/v1/approvals`) avec les mêmes policies, ce qui permet un client mobile.
- L'audit (R18) enregistre chaque soumission, décision, invalidation, délégation et escalade.

### Sécurité

- **Aucune décision par simple lien dans un e-mail.** Un e-mail contient un lien vers l'écran authentifié, jamais un bouton qui approuve: cela évite l'hameçonnage et la décision par transfert du message.
- Protection contre le rejeu et CSRF sur les décisions; second facteur récent exigé au-delà du seuil.
- Une décision porte l'empreinte du contenu vu: on ne peut pas approuver une version que l'on n'a pas eue sous les yeux.

### Cas limites

- Facture modifiée entre l'affichage et la décision: la décision est refusée, l'écran se recharge.
- Nouveau fournisseur: politique typique « premier paiement » qui exige un second niveau.
- Note de crédit: soumise à une politique dédiée ou exemptée selon le réglage.
- Facture en devise étrangère (F11): seuils évalués sur l'équivalent en EUR à la date de la facture.
- Changement d'une politique pendant que des demandes sont en cours: elles conservent la version de politique sous laquelle elles ont été créées.
- Facture arrivée après son échéance: approuvable, marquée « en retard ».

### Critères d'acceptation

1. Sans politique applicable, le BAP est `not_required` et le paiement reste possible.
2. Sur un tableau de cas de seuils (montant, fournisseur, projet), la bonne politique et les bonnes étapes sont retenues.
3. L'auteur d'une écriture ne peut pas l'approuver, ni par l'interface ni par l'API.
4. Modifier le montant après approbation invalide l'approbation et relance le circuit; modifier un libellé libre ne le fait pas.
5. Une demande non traitée dans le délai est escaladée vers la personne prévue.
6. Une délégation expire à sa date, n'est pas transitive et ne permet pas d'approuver ses propres saisies.
7. Aucune approbation n'est possible depuis un lien d'e-mail non authentifié; au-delà du seuil, la nouvelle authentification est exigée.
8. Une facture non approuvée ne peut pas être ajoutée à un lot de paiement.
9. Une facture peut être comptabilisée et sa TVA déclarée alors que son BAP est en attente, sauf réglage `bap_before_posting`.
10. Chaque événement du circuit figure dans l'audit avec l'acteur, l'empreinte et le canal.

**Tests attendus**: specs du moteur de politiques sur tableaux de cas, specs de policies par rôle, spec d'invalidation par empreinte, spec d'escalade avec `travel_to`, spec de délégation, spec de séparation des tâches, request specs de l'API, spec système du parcours mobile avec second facteur, spec d'isolation entre sociétés.

## 5. P0 · B01b Lots de paiement SEPA et contrôle des coordonnées bancaires

**Objectif.** Composer un lot avec les factures approuvées et échues, le contrôler, le faire autoriser, puis générer un fichier de virements SEPA que l'utilisateur charge et **autorise dans sa propre banque**. Cette capacité porte aussi la défense contre la fraude la plus fréquente: le changement frauduleux de coordonnées bancaires d'un fournisseur.

**Règle absolue.** LedgerFlow ne stocke aucun identifiant de connexion bancaire de l'utilisateur, n'appelle aucune API de paiement et n'initie aucun paiement. Il produit un fichier; la banque exécute après l'autorisation de l'utilisateur, dans l'application de la banque.

### Modèle de données

- `partner_bank_accounts`: tiers, IBAN (contrôle ISO 13616 et pays SEPA), BIC facultatif, nom du titulaire, statut (`unverified`, `verified`, `blocked`, `superseded`), source (Peppol, saisie, import), `verified_by`, `verified_at`, méthode de vérification (rappel téléphonique, courrier signé, relevé du fournisseur, autre), note, `first_seen_at`, `cooling_until`, compte précédent.
- `payment_batches`: société, compte bancaire débiteur, référence unique, statut (`draft`, `pending_approval`, `approved`, `exported`, `submitted`, `debited`, `partially_rejected`, `cancelled`), date d'exécution demandée, total, nombre de paiements, contrôle de somme, version du format, empreinte SHA-256 du fichier, document du fichier (F03), auteurs et dates de préparation, d'export et de soumission, demande d'approbation liée, rapport de contrôle préalable.
- `payment_items`: lot, tiers, **instantané** du compte bancaire du tiers, montant, devise, identifiant de bout en bout, communication (structurée ou libre), statut (`included`, `excluded`, `confirmed`, `rejected`, `returned`), motif d'exclusion, écriture de paiement liée (B01c).
- `payment_item_invoices`: paiement, facture (ligne d'écriture), montant imputé. Permet le paiement groupé d'un fournisseur et le paiement partiel.
- `payment_holds`: blocage d'une facture ou d'un tiers, avec motif et auteur.
- `bank_profiles`: profil d'export par banque (version du format, encodage, options, limites de taille). Les valeurs viennent de la documentation de la banque, jamais de suppositions (voir plus bas).

### Éligibilité d'une facture

Une facture n'apparaît dans « Factures à payer » que si **toutes** ces conditions sont réunies; sinon elle s'affiche grisée avec la raison exacte:

- Écriture validée, ligne ouverte sur le compte fournisseur (résiduel positif).
- `payment_status` égal à `approved` ou `not_required` (B01a), sans blocage ni litige.
- Absente de tout autre lot actif (I14).
- Échéance dans la fenêtre choisie (défaut: jusqu'à la date d'exécution plus 7 jours). Un paiement anticipé reste possible par sélection manuelle et est signalé.
- Compte bancaire du tiers `verified` et hors période d'observation.
- Devise EUR et pays du bénéficiaire dans la zone SEPA. Les autres devises sont exclues avec un message (F11).

### Composition du lot

- **Notes de crédit**: option `net_credit_notes` qui compense, pour un même fournisseur, les notes de crédit ouvertes contre les factures choisies. Si le net est nul ou négatif, aucun paiement n'est généré et le tiers est listé « à compenser » (lettrage manuel, F04).
- **Regroupement**: une facture qui porte une communication structurée est payée individuellement. Les autres peuvent être regroupées par fournisseur, avec une communication libre listant les numéros de facture dans la limite de 140 caractères.
- **Paiement partiel**: l'utilisateur peut imputer un montant inférieur au résiduel; le reste demeure ouvert.
- Limites paramétrables: nombre maximal de paiements par fichier, plafond par lot et par fournisseur.

### Contrôles préalables

Le **rapport de contrôle préalable** est déterministe. Les erreurs bloquent, les avertissements exigent un acquittement motivé.

| Contrôle | Résultat si non conforme |
| --- | --- |
| IBAN valide, zone SEPA, `verified`, hors période d'observation | Erreur |
| IBAN de la facture différent de l'IBAN du fichier tiers | Erreur tant que non vérifié |
| Facture approuvée à jour (empreinte inchangée, B01a) | Erreur |
| Date d'exécution valide: jour de règlement (calendrier configurable), non passée | Erreur |
| Doublon probable (même tiers, montant et référence dans les 90 derniers jours) | Avertissement |
| Solde bancaire projeté (R01 et R14) sous le seuil après le lot | Avertissement |
| Montant du paiement supérieur à deux fois la moyenne des factures du tiers | Avertissement |
| Plus de trois IBAN récemment créés ou modifiés dans le même lot | Avertissement |
| Caractères hors du jeu SEPA (accents, symboles) | Information: translittération listée |
| Communication structurée invalide (modulo 97) | Erreur |

Le contrôle s'exécute à la composition, à la demande d'approbation, puis **de nouveau au moment de l'export**. Toute différence entre-temps (IBAN modifié, facture invalidée) bloque l'export.

### Contrôle des coordonnées bancaires

1. Un IBAN nouveau ou modifié pour un tiers passe en `unverified` et entre dans une **période d'observation** (`cooling_hours`, 24 heures par défaut). Il est inutilisable dans un lot tant que ces deux conditions ne sont pas levées.
2. La vérification exige `bank_accounts.verify` et **une autre personne** que celle qui a créé ou modifié l'IBAN. L'écran rappelle qu'elle doit passer par un canal de contact **connu avant la demande** (numéro du fichier tiers, jamais celui de la facture ou du message qui annonce le changement), et enregistre la méthode et une note.
3. Un changement d'IBAN alerte les propriétaires. L'ancien compte est conservé (`superseded`) avec son historique d'usage.
4. **Aucune mise à jour automatique** depuis un document: ni F06, ni A09, ni l'agent ne modifient l'IBAN d'un tiers. Un IBAN différent détecté sur une facture Peppol crée seulement une alerte et une tâche (F08).
5. Le nom du titulaire est conservé tel qu'il figure sur la facture: certaines banques comparent le nom et l'IBAN du bénéficiaire lors de la soumission, et une divergence peut y bloquer le paiement.

### Approbation du lot

Le moteur de B01a s'applique avec le sujet `payment_batch`: seuils sur le total et le nombre de paiements, étapes, escalade. `distinct_payment_authorizer` interdit à la personne qui a préparé le lot de l'autoriser. Le réglage `authorizer_not_bap_giver` interdit en plus à un autorisateur d'avoir donné le BAP des factures du lot.

### Génération du fichier

- Service `Payments::Sepa::Pain001Builder`, **versionné et configurable** par profil de banque. La version du format (par exemple `pain.001.001.03` ou une version plus récente) n'est pas fixée ici: l'agent de codage la confirme auprès de l'utilisateur, pour chaque banque, à partir de la documentation de la banque et des recommandations de l'EPC, et le consigne dans `QUESTIONS.md`. Il n'invente aucune particularité propre à une banque.
- Contenu: en-tête de groupe (identifiant de message unique, date, nombre de transactions, **contrôle de somme**, initiateur), un bloc de paiement par compte débiteur et date d'exécution, une transaction par paiement (identifiant de bout en bout de 35 caractères au plus, montant en EUR, nom et IBAN du bénéficiaire, communication structurée ou libre).
- **Validation contre le schéma XSD** de la version choisie (Nokogiri), avec les limites de longueur et le jeu de caractères.
- **Déterminisme**: un même lot produit un fichier identique octet pour octet. L'empreinte SHA-256 est enregistrée, et le fichier est stocké de façon immuable dans F03.
- L'export exige `payments.export`, un lot `approved` et un second facteur récent. Il est journalisé.

### Après l'export

- Le lot devient **immuable**. Pour le changer, on l'annule (motif obligatoire) et on en crée un nouveau, avec un nouvel identifiant de message.
- L'écran affiche à l'utilisateur les valeurs à comparer avec le récapitulatif de sa banque avant de l'autoriser là-bas: nombre de paiements, contrôle de somme, total, identifiant de message, début de l'empreinte.
- L'utilisateur clique « J'ai chargé le fichier dans ma banque » (`payments.confirm`): statut `submitted`, horodaté et journalisé.

### Interface

- Écran **« Paiements »** en cinq temps: factures à payer (filtres, badges IBAN non vérifié, litige, en retard), composition du lot avec aperçu du solde projeté, contrôles, approbation, export et suivi.
- Historique des lots avec leur statut et l'accès au fichier par lien signé.
- Écran **« Coordonnées bancaires »** des tiers: statuts, vérifications en attente, historique des changements.

### Sécurité

- Fichiers et IBAN chiffrés au repos; IBAN masqué dans les journaux; téléchargements par lien signé, permission et second facteur.
- Aucun secret bancaire: un test vérifie que le schéma ne contient aucune colonne d'identifiant bancaire de l'utilisateur et qu'aucun secret de ce type n'existe dans la configuration.
- Toute action (composition, contrôle, acquittement, approbation, export, annulation, vérification d'IBAN) est journalisée dans R18.

### Cas limites

- Facture partiellement payée: seul le résiduel est proposé.
- Lot d'un seul paiement urgent: autorisé, mêmes contrôles.
- Annulation avant l'export: les factures sont libérées. Après l'export mais avant la soumission: annulation possible avec motif. Après la soumission: le lot passe en `cancel_requested`, les factures restent verrouillées jusqu'à confirmation, et l'écran rappelle qu'un rappel doit être demandé à la banque.
- Deux utilisateurs qui composent des lots avec la même facture au même moment: un seul réussit (verrou et contrainte d'unicité).
- IBAN étranger de la zone SEPA: accepté, avec contrôle du format du pays.
- Tiers sans IBAN: facture exclue avec le message correspondant.

### Critères d'acceptation

1. Seules les factures éligibles apparaissent; chaque exclusion affiche sa raison (test sur un tableau de cas).
2. Un IBAN nouveau ou modifié est inutilisable tant qu'il n'est pas vérifié par une autre personne et que la période d'observation n'est pas écoulée.
3. Un IBAN de facture différent de celui du fichier tiers bloque le paiement et crée une tâche, sans modifier le fichier tiers.
4. Le contrôle préalable bloque sur les erreurs, exige un acquittement motivé sur les avertissements, et se rejoue à l'export.
5. Le fichier est valide contre le XSD, le contrôle de somme égale la somme des paiements, et deux exports du même lot sont identiques octet pour octet (invariant I13).
6. Après l'export, le lot ne peut plus être modifié; le changer impose une annulation et un nouveau lot.
7. Une facture ne peut appartenir qu'à un lot actif, y compris sous concurrence (invariant I14).
8. La compensation des notes de crédit est correcte, et un net nul ou négatif ne génère aucun paiement.
9. L'export exige lot approuvé, permission et second facteur, et est journalisé.
10. Aucun identifiant bancaire de l'utilisateur n'est stocké; l'IBAN est masqué dans les journaux.
11. Une divergence entre le solde projeté et le seuil produit l'avertissement attendu.

**Tests attendus**: builder de fichier avec fichiers de référence et validation XSD, test de propriété sur le contrôle de somme et les arrondis, spec de chaque contrôle préalable, spec des flux de vérification d'IBAN (deux personnes, période d'observation), spec de concurrence sur l'appartenance à un lot, spec d'immuabilité après export, spec de politique et de second facteur, spec de masquage des journaux, spec système du parcours de la sélection à l'export.

## 6. P0 · B01c Confirmation, rapprochement et retours de paiement

**Objectif.** Fermer la boucle: reconnaître dans le relevé bancaire le lot que la banque a exécuté, comptabiliser les paiements, lettrer chaque facture, détecter les rejets et les retours, et montrer à tout moment où en est chaque paiement, de la facture reçue au lettrage.

### Frise d'un paiement

Facture reçue → bon à payer → dans un lot → lot exporté → soumis à la banque → débité → écritures validées → facture lettrée. Cette frise apparaît sur la fiche de la facture et sur celle du lot, avec l'auteur et l'horodatage de chaque étape.

### Reconnaissance du lot dans le relevé (règle de rapprochement F02)

B01c ajoute à F02 une règle **prioritaire**, la règle 0, appliquée aux lignes de relevé débitrices du compte du lot.

| Cas | Condition | Confiance |
| --- | --- | --- |
| A. Ligne groupée | Une ligne dont le montant égale le total du lot, dans la fenêtre de la date d'exécution (un jour avant à cinq jours ouvrés après), et dont la référence contient l'identifiant du lot ou de message | 100 |
| A'. Ligne groupée sans référence | Même condition de montant et de fenêtre, sans référence exploitable | 90 |
| B. Lignes individuelles | Une ligne par paiement: même montant, même IBAN de la contrepartie et, si présent, même identifiant de bout en bout ou même communication | 100 avec la référence, 90 sans |
| C. Lot partiel | Total débité égal au total du lot moins la somme d'un petit ensemble de paiements (recherche bornée à cinq paiements): probables rejets | 70, à confirmer |

Le format exact des enregistrements CODA que chaque banque produit pour un lot (ligne groupée ou détaillée, contenu des communications) est vérifié par l'agent de codage sur des fichiers réels anonymisés de chaque banque de l'utilisateur, jamais supposé.

### Confirmation du paiement

1. **Proposition**: « Le lot LOT-2026-0042 semble débité le 03/10 (14 paiements, 18 240,50 €) ». L'utilisateur ouvre le détail et confirme en un clic (`payments.confirm`).
2. **Écritures de paiement en brouillon**, une par paiement: débit du compte fournisseur (440) sur les lignes de facture imputées, crédit du compte bancaire, date comptable de la ligne du relevé, référence égale à l'identifiant de bout en bout, libellé « Paiement lot … – tiers ». Le lien avec `payment_items` est unique (un paiement ne génère qu'une écriture, même si l'action est répétée).
3. **Rapprochement n:1** avec la ou les lignes de relevé par le mécanisme de F02.
4. **Validation par lot** de ces brouillons (« Valider les paiements du lot », `entries.post`, et une autre personne que le préparateur si `four_eyes`).
5. **Lettrage automatique**: à la validation, chaque écriture de paiement est lettrée avec la facture qu'elle solde. Il s'agit d'une **exception explicite** au principe de validation manuelle: un lettrage exact, déterministe et réversible (F04). Un paiement partiel produit un lettrage partiel.
6. Le lot passe en `debited`; les factures lettrées passent en `paid`. R04 reflète immédiatement le nouveau solde.

**Confirmation manuelle**: si le paiement a été exécuté sans ligne de relevé retrouvée, un utilisateur avec `payments.confirm` peut confirmer avec un motif, une date et la référence bancaire. Elle n'est possible que pour un lot `submitted`, et elle est signalée dans R19 tant que le relevé correspondant n'a pas été rapproché.

### Rejets et retours

- **Rejet avant débit**: un paiement absent du débit d'un lot débité partiellement passe en `rejected`. La facture revient à `approved`, en `on_hold` avec le motif `rejected`, pour éviter un nouveau paiement automatique vers le même IBAN.
- **Retour après débit**: une ligne créditrice, dans les 30 jours suivant le débit, dont l'IBAN de contrepartie et le montant correspondent à un paiement, est proposée comme **retour**. Le clic ouvre la boîte « Extourner » (F07) préremplie pour l'écriture de paiement. La facture redevient ouverte et bloquée (`on_hold`, motif `returned`).
- **Conséquences de sécurité**: un retour ou un rejet fait repasser l'IBAN concerné en `unverified` et crée une alerte et une tâche « Contacter le fournisseur » (F08). Un IBAN qui revient est très souvent un IBAN erroné ou frauduleux.
- **Statuts de la banque** (facultatif, seconde phase): import d'un rapport d'état de paiement ISO 20022 qui met à jour le statut de chaque paiement (accepté, rejeté, règlement effectué). L'agent de codage confirme les codes et le format dans la documentation de chaque banque.

### Alertes

- Lot `submitted` sans débit retrouvé trois jours ouvrés après la date d'exécution.
- Lot `debited` dont les écritures de paiement ne sont pas validées après deux jours.
- Facture déjà lettrée au moment de la confirmation d'un paiement: **double paiement probable**. La facture passe en `disputed`, une tâche est créée, et rien n'est lettré.
- Retours et rejets, comme ci-dessus.

### Indicateurs et rapports

- Taux de lots reconnus automatiquement, délai moyen entre échéance et paiement, paiements en retard, montant des retours.
- **R14**: dès la soumission, la sortie est comptée à la date d'exécution; elle disparaît du prévisionnel au débit.
- **R06**: aucune différence artificielle, puisque l'écriture n'est créée qu'à la confirmation du débit.
- Export « Paiements exécutés » (XLSX, CSV) avec le détail par facture, pour l'auditeur.

### Sécurité et audit

Permissions `payments.confirm` et `entries.post`, séparées. Chaque confirmation, création d'écriture, validation, lettrage, rejet et retour est journalisé, IBAN masqué. Les écritures créées portent `created_via: payment_batch` et l'identifiant du lot.

### Cas limites

- La banque débite en plusieurs lignes (un bloc par date d'exécution): les lignes sont associées au même lot jusqu'à couvrir son total.
- Frais de traitement du lot: ligne séparée, traitée par les règles de F02.
- Date de débit différente de la date d'exécution demandée: acceptée dans la fenêtre, sinon proposition à confirmer.
- Paiement partiel de la facture: lettrage partiel, résiduel ouvert, facture toujours éligible à un futur lot.
- Lot annulé alors qu'une ligne de relevé le correspondrait: proposition écartée, avec message.
- Deux lots de même total proches dans le temps: aucune proposition à 100, choix laissé à l'humain.

### Critères d'acceptation

1. Sur le jeu de référence (fichiers CODA en ligne groupée et en lignes détaillées), au moins 90 % des lots sont reconnus automatiquement, avec zéro faux positif à confiance 100.
2. La confirmation crée une écriture de paiement en brouillon par paiement, exactement une, même si l'action est répétée.
3. Le débit bancaire du lot égale le total des paiements confirmés (invariant I13).
4. La validation par lot déclenche le lettrage exact; le résiduel d'un paiement partiel est correct; R04 est à jour.
5. Un retour est proposé comme extourne, la facture redevient ouverte et bloquée, et l'IBAN repasse en non vérifié.
6. Une facture déjà lettrée donne une alerte de double paiement et n'est pas lettrée une seconde fois.
7. Un lot soumis sans débit retrouvé déclenche l'alerte au délai prévu.
8. La confirmation manuelle exige un motif et reste visible dans R19 tant que le relevé n'est pas rapproché.
9. Aucune écriture n'est validée sans action humaine, hors le lettrage exact prévu.

**Tests attendus**: spec de la règle 0 sur des fichiers CODA réels anonymisés de plusieurs banques (lignes groupées, détaillées, partielles), spec d'idempotence de la confirmation, spec du lettrage automatique exact et partiel, spec des rejets, retours et double paiement, spec des alertes avec `travel_to`, spec d'invariant I13, spec système de la frise du paiement.

## 7. P1 · B03a États de la comptabilité à une date de connaissance

**Objectif.** Permettre de voir la comptabilité **telle qu'elle était à un instant donné**, et non seulement telle qu'elle est aujourd'hui. C'est la question de tout réviseur: « quel bilan avait-on présenté le 15 janvier, avant les régularisations ? ». Répondre à cela, de façon démontrable, est l'une des fonctions les plus rares et les plus convaincantes d'un logiciel comptable.

### Deux axes de temps

| Axe | Question | Paramètre |
| --- | --- | --- |
| Date comptable | À quelle période appartient l'écriture ? | `as_of` ou période (déjà en place dans les rapports) |
| **Date de connaissance** | Que savait le logiciel à cet instant ? | **`known_at`** (nouveau) |

Exemple: la balance au 31/12/2025 **connue le 15/01/2026** peut différer de la même balance connue aujourd'hui, si des écritures datées de 2025 ont été validées depuis. Les deux sont exactes; elles répondent à deux questions différentes.

### Ce qui rend la reconstruction fiable

1. **`posted_at` immuable.** Chaque écriture porte l'instant de sa validation, fixé par la base de données, jamais modifiable (trigger, dans la lignée de F01). Une écriture validée ne se supprime pas et ne se modifie pas: on l'extourne, et l'extourne est une nouvelle écriture avec son propre `posted_at`.
2. **Ordre monotone par société.** La validation prend un verrou consultatif par société (`pg_advisory_xact_lock`) et attribue un numéro de séquence `posted_seq`. `posted_at` et `posted_seq` sont donc monotones pour une société. Cela évite qu'une transaction démarrée avant T mais confirmée après T apparaisse ou disparaisse de façon incohérente dans une vue à T. En interne, un `known_at` est converti en dernier `posted_seq` dont le `posted_at` est antérieur ou égal.
3. **Lettrage daté.** Les instants de lettrage et de délettrage (`matched_at`, `unreconciled_at`, `reconciliation_items.created_at`, F04) permettent de reconstruire les résiduels et la balance âgée à l'instant demandé.
4. **Données de référence versionnées.** `master_data_versions` (type, identifiant, `valid_from`, `valid_to`, attributs, auteur) conserve l'historique des comptes (libellé, classe, type), tiers (nom, numéro de TVA), codes TVA et rattachements de rubriques (déjà datés par R07). Un compte renommé s'affiche avec son ancien nom dans une vue antérieure.
5. **Historique des verrous** (`period_locks`), des versions de budget synchronisées (R11) et des pièces (F03: `created_at`) pour reconstruire l'environnement.
6. **Début d'historique garanti** (`history_start`, par société et par exercice). Avant cette date, la reconstruction n'est pas garantie: la vue est refusée avec une explication. Pour les écritures reprises par F05, `posted_at` vaut la date de validation d'origine si la source la fournit (`legacy_posted_at`), sinon l'instant de l'import, marqué `posted_at_source = import`.

Les **brouillons** n'existent pas dans une vue historique: un brouillon n'est pas « connu » tant qu'il n'est pas validé.

### Rapports concernés

`Reports::Filters` reçoit un champ optionnel `known_at` (horodatage avec fuseau). La vue `posted_lines` expose `posted_seq`, et chaque requête ajoute la condition correspondante. Résiduels et lettrage sont recalculés avec les instants de lettrage; libellés et hiérarchies avec `master_data_versions`.

| Vague P1 (supportés) | Plus tard |
| --- | --- |
| R01, R02, R03, R04, R05, R07, R08, R09 | R06 (comparaison avec le figé), R11, R12, R13, R15, R16 |

Un rapport non supporté désactive le sélecteur de vue historique avec une explication.

### Interface

- **Sélecteur « Vue historique »** dans l'en-tête de chaque rapport supporté: date et heure avec fuseau explicite, et des **repères** générés à partir d'événements réels: « à la dernière clôture de mois », « au moment du dépôt de la TVA du T3 », « à la dernière émission d'un certificat » (B03c), « lors de mon dernier passage ».
- **Bandeau persistant**: « Vue historique — état connu le 15/01/2026 à 09:30. Lecture seule. » avec « Revenir à aujourd'hui ».
- **Lecture seule stricte**: toutes les actions sont désactivées. Les liens de drill-down conservent `known_at`; les pièces affichées sont celles qui existaient alors.
- **Exports**: filigrane « Vue historique au … » et mention du `known_at` dans les métadonnées (PDF, XLSX, CSV).
- Un lien « Comparer avec aujourd'hui » ouvre B03b.
- Pas de lien de partage: un auditeur externe consulte avec son propre accès (F01).

### Témoins de vérité

La reconstruction est validée par des **témoins** indépendants: les instantanés déjà figés.

- Pour chaque instantané (clôture F10, TVA déposée R09, rapprochement figé R06, consolidation figée F12), la tâche `TimeTravel::WitnessCheck` recalcule le rapport correspondant avec `known_at` égal à l'instant de l'instantané et le compare à la valeur figée. Tout écart est une anomalie **bloquante** de R19 (nouveau contrôle **C18**, « reconstruction historique divergente d'un instantané figé »).
- Le test de séquences aléatoires de F (opérations comptables aléatoires) enregistre des instantanés à des instants aléatoires et vérifie que la vue historique les reproduit exactement.

### Performance et cache

- Index partiel `(company_id, posted_seq)` sur les lignes validées.
- Budgets: au plus 20 % au-dessus du rapport courant équivalent.
- Un résultat pour un `known_at` passé est **immuable**: il se met en cache sans expiration, avec une clé qui contient les filtres, `known_at` et la version du schéma du rapport.

### Agent IA

Les outils de rapports d'A02 acceptent `known_at`. Toute réponse fondée sur une vue historique énonce « état connu au … », en plus de la portée habituelle du §8 de la spécification de l'agent.

### Cas limites

- `known_at` dans le futur ou égal à maintenant: équivaut à la vue courante, sans bandeau.
- Changement d'heure d'été: le sélecteur affiche le décalage UTC explicite; une heure ambiguë est refusée avec un choix.
- Écritures reprises par F05 avec `posted_at` d'import: pour ces périodes, `history_start` est postérieur à l'import; les vues antérieures sont refusées.
- Tiers fusionné ou renommé: son nom historique apparaît dans une vue antérieure, son identifiant reste le même.
- Utilisateur dont les droits sont restreints par journal: la restriction s'applique à la vue historique.
- Pièce supprimée après archivage: n'existe plus; la vue le signale plutôt que d'afficher un lien mort.

### Critères d'acceptation

1. Pour tout rapport supporté, `known_at` égal à maintenant donne exactement le rapport courant (jeu de référence).
2. La vue historique reproduit à l'euro près chaque instantané figé (clôtures, TVA déposée, rapprochements figés).
3. Une écriture validée à T2 est absente d'une vue à T1 < T2 et présente à T2; une extourne n'apparaît qu'à partir de son propre instant.
4. R04 à un instant antérieur montre ouverte une facture lettrée plus tard, et R04 aujourd'hui la montre soldée.
5. Un compte renommé porte son ancien nom dans une vue antérieure au renommage.
6. Une vue avant `history_start` est refusée avec l'explication.
7. Sous validations concurrentes de plusieurs processus, `posted_at` et `posted_seq` sont monotones par société, et une transaction confirmée après T n'apparaît jamais dans une vue à T (test de concurrence).
8. En vue historique, aucune action n'est possible, y compris par l'API (réponse `409` avec le code `historical_view`).
9. Les mêmes droits, y compris les restrictions par journal, s'appliquent qu'en vue courante.
10. Les exports portent le `known_at`; un résultat historique mis en cache est identique à son recalcul.
11. Les vues historiques restent à moins de 20 % du budget de performance du rapport courant.
12. `WitnessCheck` détecte une divergence provoquée volontairement et crée l'anomalie C18.

**Tests attendus**: specs de requête avec `known_at` sur tableaux de cas (validation, extourne, lettrage, renommage, verrouillage), test de séquences aléatoires avec instantanés, test de concurrence sur `posted_seq` avec plusieurs processus, spec de refus avant `history_start`, spec de lecture seule par l'interface et par l'API, spec de `WitnessCheck` et de C18, spec de cache immuable, spec système du sélecteur et du bandeau.

## 8. P1 · B03b Rapport de changements entre deux moments

**Objectif.** Répondre à « qu'est-ce qui a changé depuis mon dernier passage ? » avec des chiffres qui se recoupent et une piste claire vers chaque changement. C'est l'outil du comptable qui reprend un dossier, du réviseur qui contrôle après coup, du dirigeant qui veut comprendre pourquoi un chiffre a bougé depuis hier. Nouveau rapport **R21**.

### Paramètres

- **Deux instants** `T1` et `T2` (dates de connaissance de B03a). `T2` vaut par défaut « maintenant ».
- **Date d'arrêté** `as_of` commune aux deux instants (défaut: fin de l'exercice courant), ou période de reporting: on compare toujours le même périmètre comptable connu à deux moments différents.
- Filtres: classes ou comptes, journaux, acteurs, catégories de changement.
- **Repères prédéfinis**: « depuis hier 18 h », « depuis mon dernier passage », « depuis la dernière clôture de mois », « depuis le dernier certificat » (B03c), « entre deux instants ».
- **Dernier passage**: `user_visits` (utilisateur, société, dernier passage) sert uniquement à proposer `T1` par défaut. La donnée est personnelle à l'utilisateur, visible, effaçable, et désactivable par un réglage de société.

### Contenu du rapport

1. **Résumé**: nombre d'écritures ajoutées, extournes, lettrages et délettrages, changements de paramétrage, verrouillages et déverrouillages de périodes; total des mouvements; comptes touchés; personnes intervenues.
2. **Impact sur les états**: valeur à `T1`, valeur à `T2` et variation, pour les rubriques du bilan et du compte de résultat (R07, R08), la trésorerie, les grilles de TVA (R09) et l'encours échu (R04). Chaque colonne provient du **même rapport** calculé avec `known_at` égal à `T1`, puis à `T2`.
3. **Impact par compte**: comptes dont le solde a le plus varié, avec drill-down vers R02 en `known_at` = `T2`.
4. **Détail chronologique**, par catégorie:
   - Écritures ajoutées: numéro, date comptable, date de validation, auteur, journal, montant, libellé.
   - Extournes et corrections, avec motif.
   - Lettrages et délettrages, avec motif.
   - Paramétrage: plan comptable, TVA, rattachements de rubriques (depuis `master_data_versions`).
   - Verrouillages et déverrouillages, avec motif.
   - Pièces ajoutées ou archivées (F03), paiements et lots (B01), changements d'IBAN.
5. **Alertes de revue**, calculées à partir des changements:
   - Écriture **tardive**: validée plus de `late_days` (15 par défaut) après sa date comptable, ou datée dans une période qui avait été passée en revue ou verrouillée.
   - Modification obtenue par une fenêtre de déverrouillage (F01).
   - Changement de rattachement de rubrique qui déplace un montant significatif entre deux lignes d'états.
   - Extournes fréquentes pour un même auteur, imports de masse (F05, F13), délettrages, changements d'IBAN.

### Règle de bouclage

Pour chaque compte, la variation de solde entre `T1` et `T2` **doit égaler** la somme des mouvements des lignes validées entre ces deux instants, à `as_of` constant (**invariant I12**). Le rapport affiche le résultat de ce contrôle: « Somme des variations = somme des mouvements, écart 0,00 ». Un écart s'affiche en rouge, bloque l'export officiel et crée une anomalie dans R19.

### Règles

- Les brouillons n'apparaissent jamais. Les écritures reprises par un import de masse sont marquées comme telles.
- Une écriture validée puis extournée dans l'intervalle apparaît comme une **paire**, marquée « neutre », avec un interrupteur pour masquer les paires neutres.
- Les événements simultanés sont ordonnés par `posted_seq`.
- L'utilisateur ne voit que les changements sur des données auxquelles il a accès. Les **noms des auteurs** ne s'affichent que pour les rôles disposant de `audit.view`; les autres voient « un utilisateur de la société ».
- `T1` antérieur à `history_start`: refusé avec l'explication. `T1` postérieur à `T2`: refusé, avec proposition d'inverser.
- Étendue très large (un an): agrégation par mois, avec détail sur demande.

### Revue et suivi

- Un réviseur peut marquer un changement comme **revu** (`change_reviews`: objet, événement, relecteur, date, commentaire). L'état revu est visible de tous et journalisé.
- Depuis n'importe quel changement: « Créer une tâche » (F08) ou « Demander à l'agent » (A08).
- **Abonnement aux alertes**: un propriétaire ou un réviseur peut recevoir une notification (A10) pour les écritures tardives au-dessus d'un seuil, les changements dans une période verrouillée et les changements d'IBAN, avec regroupement et limitation.

### Interface

- Page **« Ce qui a changé »** accessible du menu et depuis le sélecteur « Comparer avec un autre moment » de chaque rapport supporté.
- Barre supérieure avec les deux instants et les repères prédéfinis; cartes de résumé; trois onglets: Impact, Détail, Alertes.
- Export PDF et XLSX du rapport, avec les paramètres, les deux instants et le résultat du bouclage, prêts à être remis à un auditeur.
- **Agent**: l'outil `get_changes_between` alimente le résumé « Ce qui a changé depuis hier » (A10) et permet à A05 d'expliquer une variation entre deux moments.

### Performance

Pour 10 000 changements, l'ouverture et le résumé prennent moins de 3 secondes. Le détail est paginé. Les deux calculs d'impact sont immuables quand `T2` est passé et sont donc mis en cache (B03a).

### Cas limites

- Deux écritures validées dans la même seconde: ordre garanti par `posted_seq`.
- Auteur dont le compte a été supprimé ou archivé: nom conservé dans l'historique, marqué « ancien utilisateur ».
- Changement dans une pièce liée seulement (aucun mouvement comptable): listé dans la catégorie Pièces, sans effet sur l'impact chiffré.
- Restriction d'accès par journal: le bouclage est calculé sur le périmètre visible et l'indique.
- Fuseau horaire: les deux instants sont affichés avec leur décalage explicite.

### Critères d'acceptation

1. Le bouclage est exact sur le jeu de référence: pour chaque compte, variation = somme des mouvements entre `T1` et `T2` (invariant I12).
2. Une écriture validée entre `T1` et `T2` apparaît dans le détail et dans l'impact, une écriture antérieure ou postérieure n'y apparaît pas.
3. Une paire validation et extourne est marquée neutre et n'altère pas les soldes de l'impact.
4. Une écriture datée dans une période verrouillée et obtenue par une fenêtre de déverrouillage déclenche l'alerte prévue.
5. Une écriture validée 40 jours après sa date comptable déclenche l'alerte « tardive » (seuil de 15 jours).
6. Les noms des auteurs sont masqués pour un rôle sans `audit.view`.
7. `T1` avant `history_start` est refusé avec l'explication.
8. Le marquage « revu » est visible de tous et journalisé.
9. Le rapport de 10 000 changements s'ouvre en moins de 3 secondes.
10. Un écart de bouclage provoqué volontairement bloque l'export officiel et crée l'anomalie dans R19.

**Tests attendus**: spec de bouclage sur séquences aléatoires d'opérations, spec des catégories de changements, spec des alertes de revue avec `travel_to`, spec de masquage des auteurs, spec de neutralisation des paires, spec de performance, spec système du parcours « depuis mon dernier passage ».

## 9. P1 · B03c Ancrage, certificat d'intégrité et vérification indépendante

**Objectif.** Permettre à LedgerFlow de **prouver** que l'état de la comptabilité à un instant donné n'a pas été altéré, par un certificat que n'importe quel tiers (auditeur, banque, client, autorité) peut **vérifier sans avoir accès à l'application**. Un logiciel qui se contente de dire « faites-moi confiance » est ordinaire; un logiciel qui permet de vérifier est rare.

### Ce que le certificat prouve, et ce qu'il ne prouve pas

Cette section est répétée sur chaque certificat, en clair.

| Il prouve | Il ne prouve pas |
| --- | --- |
| Que l'ensemble des écritures validées jusqu'à l'instant `T` correspond à une empreinte cryptographique précise, calculée à des moments antérieurs et enchaînée | Que les écritures sont **exactes**, complètes ou conformes à la réglementation |
| Que le journal d'audit est intact et lié à ces écritures | Que les pièces justificatives sont authentiques (seulement qu'elles n'ont pas changé depuis leur dépôt) |
| Que les invariants comptables tenaient à l'émission | Une opinion d'audit ou d'expert-comptable |
| Avec un horodatage externe: que ces empreintes existaient à la date de l'horodatage | Que rien n'a été omis **avant** le début de l'ancrage (l'historique antérieur est couvert par un ancrage rétroactif signalé comme tel) |
| Que le certificat a été émis par cette instance de LedgerFlow (signature) | Sans horodatage externe: une protection contre un opérateur qui détiendrait à la fois la base et la clé de signature |

### Étape 1 · Empreinte de contenu des écritures

- À la validation, `Ledger::PostEntry` calcule `journal_entries.content_hash` = SHA-256 de la **sérialisation canonique** (JSON canonique selon RFC 8785) de l'écriture: société, numéro, journal, dates comptable et de pièce, référence, lignes (numéro d'ordre, compte, débit et crédit en chaînes décimales, devise, montant en devise, taux, code TVA, échéance, libellé), `posted_at`, `posted_seq` et auteur de la validation.
- Sont **exclus** les états qui changent légitimement après validation: lettrage, résiduel, liens vers des pièces.
- L'empreinte est calculée dans la même transaction que la validation et rendue immuable par trigger.

### Étape 2 · Ancrages

- Table `ledger_anchors` (société, borne de `posted_seq` de début et de fin, nombre d'écritures, **racine de Merkle**, empreinte de la tête de la chaîne d'audit, empreinte de l'ancrage précédent, empreinte de l'ancrage, date, type: `nightly`, `on_demand` ou `retroactive`, jeton d'horodatage externe).
- **Arbre de Merkle** sur les `content_hash` dans l'ordre de `posted_seq`: feuille = SHA-256(0x00 ‖ empreinte), nœud = SHA-256(0x01 ‖ gauche ‖ droite), nœud impair remonté tel quel (construction du type de la RFC 6962).
- `anchor_hash` = SHA-256(empreinte précédente ‖ bornes ‖ racine ‖ nombre ‖ tête de la chaîne d'audit ‖ date). L'ancrage **lie** ainsi les écritures au journal d'audit.
- Un job nocturne crée l'ancrage du jour. Un ancrage `on_demand` est créé à l'émission d'un certificat pour l'instant présent.
- **Ancrage rétroactif** unique à l'activation, pour l'historique existant. Il est signalé comme tel sur tout certificat qui le couvre.

### Étape 3 · Horodatage externe (recommandé)

- L'empreinte de chaque ancrage peut être envoyée à une **autorité d'horodatage** selon le protocole RFC 3161. Seule l'empreinte quitte l'application, jamais une donnée comptable. Le jeton est stocké dans l'ancrage et se vérifie avec des outils standard.
- Le choix du prestataire (par exemple un prestataire de services de confiance qualifié au sens du règlement eIDAS, qui donne un poids juridique plus fort) est une **décision à prendre avec l'utilisateur**: l'agent de codage présente les options, leur coût et leurs conséquences avant de choisir.
- Sans horodatage externe, le certificat l'écrit explicitement et la preuve repose sur la seule clé de l'instance.

### Étape 4 · Signature et clés

- Le certificat est signé en **Ed25519**. Table `certificate_signing_keys` (identifiant, clé publique, empreinte, statut, dates de création, de retrait et de révocation).
- La clé privée est protégée par le système de gestion de secrets (KMS ou `credentials` chiffrés), jamais dans le dépôt ni dans la base. Rotation annuelle; les anciennes clés publiques sont conservées pour toujours afin de vérifier les certificats anciens.
- Les clés publiques sont publiées à une adresse fixe (`/.well-known/ledgerflow/keys.json`) et **chaque certificat inclut la clé publique et son empreinte**. Le certificat recommande à son destinataire de comparer cette empreinte par un autre canal.
- Procédure de compromission: révocation de la clé, avis public, nouvelle clé, réémission possible des certificats concernés.

### Le certificat (`integrity_certificates`)

Identifiant (UUID), société, date et auteur de l'émission, **instant couvert** `T`, exercice ou période, plage d'ancrages et dernière empreinte d'ancrage, nombre d'écritures et de lignes, total des débits égal au total des crédits, résultats des invariants I1 à I15 à l'émission, état de la chaîne d'audit (tête, longueur, résultat de `audit:verify`), état des pièces (dernier `documents:verify`), périodes verrouillées, nombre d'anomalies bloquantes ouvertes (R19), état des témoins (B03a), version du logiciel et hash de son manifeste, **niveau de divulgation**, signature, référence du jeton d'horodatage, adresse et QR code de vérification.

- **Niveaux de divulgation**: `minimal` (empreintes, plages, résultats d'invariants, sans montants), `standard` (en plus les totaux et un résumé par classe de comptes), `full` (en plus le paquet de vérification complet).
- **Instants possibles**: « maintenant » (un ancrage est créé à l'émission) ou la borne d'un ancrage passé, proposée dans une liste (« Ancrage du 31/12/2025 03:00 »). Un instant quelconque entre deux ancrages n'est pas certifiable.
- **Conditions d'émission**: permission `integrity.issue` et second facteur récent. Si la chaîne d'audit, les ancrages ou les invariants I1 et I2 sont défaillants, l'émission est **refusée** et une anomalie bloquante est créée. Toute autre défaillance est listée comme **réserve** en tête du certificat.
- **Clôture**: l'étape 17 de F10 émet automatiquement un certificat `standard` pour l'exercice, inclus dans la liasse (R20).
- Un certificat n'est pas révoqué parce que des écritures ultérieures modifient les périodes couvertes: il atteste l'état à `T`. Il peut l'être pour une erreur d'émission, avec motif.

### Le paquet de vérification

Archive ZIP produite pour le niveau `full`, avec chiffrement optionnel par phrase secrète:

- `certificate.json` (signé) et `certificate.pdf` (lisible, avec le tableau « prouve / ne prouve pas »).
- `entries.ndjson`: écritures en forme canonique, dans l'ordre de `posted_seq`.
- `anchors.json` avec les jetons d'horodatage.
- `audit_chain.ndjson`: pour chaque événement, son **empreinte de contenu**, l'empreinte précédente et l'empreinte de chaîne, **sans le contenu**.
- `documents_manifest.json`: empreinte SHA-256 de chaque pièce et écritures liées.
- `manifest.json` avec l'empreinte de chaque fichier.

Ce paquet contient des données comptables. Il se transmet par un canal sécurisé.

**Évolution de R18.** Pour qu'un tiers puisse vérifier la chaîne d'audit **sans** en connaître le contenu, chaque événement conserve son `content_digest` (SHA-256 du contenu) et la chaîne devient `hash = SHA-256(hash précédent ‖ content_digest ‖ métadonnées)`. Cette **version 2** de la chaîne démarre à l'activation, ancrée sur la tête de la version 1. L'agent de codage propose la migration; il ne réécrit jamais les événements existants.

### Vérification indépendante

- **Outil `ledger-verify`**: script autonome en Ruby, sans dépendance à Rails ni à l'application (bibliothèque standard et OpenSSL), placé dans `tools/ledger-verify/` avec son propre dépôt possible. Il prend le paquet et, en option, l'empreinte de clé publique attendue et le certificat de l'autorité d'horodatage.
  1. Valide la structure de `certificate.json` et des fichiers.
  2. Recalcule chaque `content_hash` depuis `entries.ndjson`.
  3. Reconstruit les racines de Merkle et les compare aux ancrages.
  4. Vérifie l'enchaînement des ancrages et de la chaîne d'audit.
  5. Vérifie la signature Ed25519 et l'empreinte de la clé.
  6. Vérifie les jetons RFC 3161 (par exemple avec `openssl ts -verify`).
  7. Recalcule les totaux et compare avec ceux du certificat.
  8. Sur option, compare les pièces fournies avec `documents_manifest.json`.
  9. Affiche `PASS` ou `FAIL` avec le détail, code de sortie non nul en cas d'échec. Pour un certificat `minimal`, il vérifie ce qui est vérifiable (signature, ancrages, horodatage, chaîne) et le dit.
- **Page publique** `/verify/:id` sans connexion: validité de la signature, date d'émission, niveau, empreintes, et l'état **depuis l'émission**: « aucune écriture validée depuis » ou « N écritures validées depuis, dont M datées dans la période couverte (voir le rapport de changements) ». Aucun montant ni nom n'est affiché; le nom de la société n'apparaît que si le réglage le permet. Identifiants non devinables, limitation de débit.

### Détection d'altération

- Job nocturne `Integrity::SelfCheck`: recalcule les `content_hash` des écritures des sept derniers jours et d'un échantillon de 1 % du reste, vérifie les racines de Merkle des ancrages récents et la chaîne d'audit. Une vérification complète tourne chaque semaine et à la demande.
- Une divergence crée une anomalie **bloquante** (nouveau contrôle **C19**, « intégrité de l'ancrage compromise »), une alerte aux propriétaires et un événement de sécurité.
- Les triggers de F01 empêchent déjà la modification d'écritures validées; l'ancrage détecte ce qu'un accès direct à la base pourrait contourner.

### Interface

- Page **« Intégrité »**: dernier ancrage, dernière vérification complète, dernier jeton d'horodatage, état des invariants et des témoins, clés en vigueur.
- Bouton **« Émettre un certificat »**: choix de l'instant, du périmètre, du niveau de divulgation, du destinataire (libellé), de la phrase secrète du paquet.
- Liste des certificats émis avec statut, téléchargement (PDF, JSON, paquet) et bouton « Vérifier maintenant ».
- Réglages réservés aux propriétaires (`integrity.configure`): autorité d'horodatage, niveau par défaut, affichage public du nom de la société.
- Indicateur discret dans l'en-tête de l'application: « Intégrité vérifiée aujourd'hui à 03:00 ».

### Sécurité et audit

Émission, téléchargement, révocation, changement de réglages et rotation de clé sont journalisés (R18). Aucune clé privée n'apparaît dans les journaux ni dans les sauvegardes non chiffrées.

### Cas limites

- Aucun ancrage disponible à l'instant demandé: proposition des ancrages existants les plus proches.
- Autorité d'horodatage indisponible: l'ancrage est créé sans jeton et un job réessaie; le certificat émis entre-temps l'indique.
- Écritures importées (F05): couvertes par l'ancrage rétroactif, signalé sur le certificat.
- Rotation de clé entre l'émission et la vérification: la clé est retrouvée par son identifiant.
- Paquet volumineux (plus de 500 000 écritures): production en tâche de fond, flux, lien signé.

### Critères d'acceptation

1. Deux calculs de `content_hash` de la même écriture donnent la même empreinte; toute modification d'un champ de contenu la change.
2. La racine de Merkle recalculée à partir des écritures d'un ancrage égale la racine enregistrée, et la chaîne d'ancrages est ininterrompue (invariant I15).
3. `ledger-verify` renvoie `PASS` sur un paquet intact, sans accès à l'application.
4. Modifier volontairement un montant dans `entries.ndjson`, dans la base ou un ancrage fait échouer `ledger-verify` avec l'identifiant de l'écriture ou de l'ancrage en cause.
5. Une altération directe en base (contournant l'application) est détectée par `Integrity::SelfCheck` et crée C19.
6. La signature Ed25519 se vérifie avec la clé publique publiée, et une clé retirée reste utilisable pour vérifier les anciens certificats.
7. Un jeton RFC 3161 valide se vérifie avec un outil standard; l'absence de jeton est indiquée sur le certificat.
8. L'émission est refusée si la chaîne d'audit ou les invariants I1 et I2 sont défaillants; toute autre défaillance figure comme réserve.
9. La page publique n'affiche ni montant ni nom sans autorisation, et elle indique les modifications survenues depuis l'émission.
10. Le certificat contient le tableau « prouve / ne prouve pas » et signale l'ancrage rétroactif quand il s'applique.
11. La chaîne d'audit en version 2 se vérifie sans le contenu des événements, et la migration ne modifie aucun événement existant.
12. Aucune clé privée n'apparaît dans les journaux, la base ou le dépôt (contrôle automatique).

**Tests attendus**: vecteurs de test pour la canonicalisation et l'arbre de Merkle (jeux de référence publics), tests de propriété sur l'immuabilité des empreintes, spec d'ancrage nocturne et à la demande, spec de `ledger-verify` sur paquets intacts et altérés (chaque type d'altération), spec de la signature et de la rotation de clés, spec de RFC 3161 avec autorité de test, spec de `SelfCheck` avec altération directe, spec de la page publique, spec de la migration de la chaîne d'audit, spec des niveaux de divulgation.

## 10. P2 · B02a Portail client: identité, accès et publication

**Objectif.** Ouvrir à des personnes extérieures (dirigeant, collaborateur, associé) un espace simple et sûr, sans jamais leur donner accès à la comptabilité elle-même. Le principe directeur est **« le portail publie, il n'expose pas »**: un externe voit ce que le cabinet a choisi de lui montrer, sous forme de publications figées, et il peut déposer des pièces et répondre. Cette capacité pose les fondations de B02b et B02c; c'est elle qui porte l'essentiel du risque, et elle est donc traitée en premier dans le portail.

### Architecture d'isolation

- **Origine séparée**: sous-domaine dédié (par exemple `portail.<domaine>`), cookies propres à cet hôte, aucune session partagée avec l'application interne, `Content-Security-Policy` stricte, aucun script tiers, en-têtes de sécurité complets (HSTS et autres).
- **Identité séparée**: modèle `PortalUser` distinct de `User` (authentification multi-modèles existante). Une même personne qui est aussi utilisateur interne possède deux identités sans lien.
- **Code séparé**: espace `Portal::` avec son propre contrôleur de base. Le code du portail **ne peut pas appeler** les services de rapports, `Ledger::*` ni les modèles comptables. Il ne lit que des tables et des vues `portal_*` alimentées par des services internes. Un test statique fait échouer la suite si une classe du portail référence un service hors d'une liste blanche.
- **Privilèges de base de données**: dès que le déploiement le permet, le portail se connecte avec un rôle PostgreSQL limité à ces tables et vues (lecture, et écriture sur les seuls dépôts et réponses).
- **Identifiants opaques**: aucun identifiant séquentiel n'est exposé. Chaque objet visible est désigné par un jeton aléatoire. Toute lecture passe par la **portée du droit** de l'utilisateur (`current_grant.scope`), jamais par `Modèle.find(params[:id])`.

### Modèle de données

- `portal_users`: e-mail unique, nom, langue, statut (`invited`, `active`, `suspended`, `revoked`), facteurs d'authentification (clés WebAuthn, secret TOTP chiffré), dernier accès, créé par, identité vérifiée par et à quelle date.
- `portal_grants`: utilisateur du portail, société, rôle, capacités, expiration, révocation, créé par.
- `portal_invitations`: hash du jeton, e-mail, droits prédéfinis, expiration (7 jours), utilisation.
- `portal_publications`: société, type (`monthly_report`, `situation`, `vat_summary`, `document_request`, `other`), titre, période, fichiers (documents F03 avec leur SHA-256), publié par et le, visibilité, version et publication remplacée, `requires_approval`, expiration, statut (`draft`, `published`, `withdrawn`).
- `portal_events`: journal des actions du portail (connexion, consultation, téléchargement, dépôt, réponse), recopié dans R18 avec `actor_type = portal_user`.
- `organization_branding`: logo, couleurs, nom d'affichage, domaine personnalisé facultatif.

### Rôles du portail

| Capacité | Dirigeant | Collaborateur | Lecteur |
| --- | --- | --- | --- |
| Déposer des pièces (B02b) | Oui | Oui | Non |
| Répondre aux questions (B02c) | Oui | Oui | Non |
| Voir les lignes bancaires à justifier | Oui | Oui | Non |
| Voir les publications et le tableau de bord | Oui | Selon droits | Selon droits |
| Valider les comptes (B02c) | Oui | Non | Non |
| Demander l'accès d'une autre personne | Oui | Non | Non |

Les droits par défaut sont **refusés**: une capacité n'existe que si elle figure dans `portal_grants`. Un client ne peut pas s'inviter lui-même ni inviter quelqu'un: il **demande** un accès, que le cabinet accorde (`portal.manage`).

### Invitation et authentification

1. Un utilisateur interne invite par e-mail avec des droits prédéfinis. Le jeton est à usage unique, stocké sous forme de hash, valable 7 jours.
2. À l'activation, la personne **configure obligatoirement un second facteur** avant d'accéder à quoi que ce soit: clé d'accès (WebAuthn, préférée) ou application TOTP, avec codes de secours.
3. Les utilisateurs qui peuvent **valider les comptes** doivent en plus avoir leur **identité vérifiée** par le cabinet (contact hors ligne), consignée dans `identity_verified_by` et `identity_verified_at`.
4. **Pas de récupération par e-mail seul**: en cas de perte du second facteur, le cabinet réinitialise et réinvite. Cela évite qu'une boîte de messagerie compromise suffise.
5. Sessions de 30 minutes d'inactivité et 12 heures au plus. Nouvelle authentification (second facteur) avant une validation de comptes.
6. Verrouillage après cinq échecs, limitation de débit par adresse et par compte, notification par e-mail d'une connexion depuis un nouvel appareil ou un nouveau pays, liste des appareils avec révocation.

### Publications

- Le cabinet choisit « Publier vers le portail »: fichiers (par exemple les PDF de R07, R08, un rapport de gestion), titre, période, message, personnes destinataires. Les fichiers sont générés par les exporteurs de rapports, avec leur `known_at` si la publication vient d'une vue historique, et **leur SHA-256 est enregistré**.
- Une publication est **immuable**. Corriger revient à publier une nouvelle version qui remplace la précédente (marquée « remplacée »). Retirer la rend invisible au client mais la conserve pour l'audit.
- Une publication peut exiger la **validation du client** (B02c) et peut inclure un certificat d'intégrité `minimal` ou `standard` de B03c.
- Téléchargements par lien signé de cinq minutes. Option de **filigrane** (nom du destinataire et date) sur les PDF téléchargés pour décourager la diffusion.

### Image de marque

Logo, couleurs, nom d'affichage et expéditeur des e-mails au nom du cabinet. Un **domaine personnalisé** est possible avec certificat TLS automatique. Toute combinaison de couleurs qui ne respecte pas le contraste **WCAG AA** est refusée à l'enregistrement.

### Notifications

E-mails aux clients avec **compteurs et liens**, sans montants ni noms (§2.5), envoyés depuis un domaine correctement authentifié (SPF, DKIM, DMARC). Préférences de fréquence par utilisateur; les alertes de sécurité ne se désactivent pas.

### Revue des accès et départ des personnes

- Rapport trimestriel **« Revue des accès »**: tous les droits actifs, dernier accès, droits inactifs depuis 90 jours signalés, révocation en un clic.
- Suspension automatique après 180 jours sans connexion (réglable).
- Révocation **immédiate**: effective à la requête suivante, sessions invalidées.

### Audit et supervision

- Écran interne **« Activité du portail »**: connexions, consultations, téléchargements, dépôts, réponses, par client et par personne.
- Alertes sur les comportements inhabituels: connexion depuis un nouveau pays, téléchargements en rafale, tentatives d'accès à des objets hors périmètre.
- Toutes les actions sont dans R18 avec le type d'acteur.

### Hors périmètre

L'agent IA n'est **pas** exposé au portail. Aucun accès en direct au grand livre, aux rapports ou à l'API interne. Aucun accès anonyme par simple lien, hormis la page publique de vérification d'un certificat (B03c), qui ne montre aucune donnée.

### Cas limites

- Même adresse e-mail pour plusieurs sociétés: une identité, plusieurs droits distincts, sans mélange.
- Adresse partagée (comptabilite@…): déconseillée, avertissement à l'invitation; les validations exigent une identité personnelle.
- Publication retirée pendant que le client la consulte: message clair au prochain chargement.
- Droit expiré en cours de session: refus à la requête suivante.
- Changement d'adresse e-mail: nouvelle vérification et nouvelle invitation par le cabinet.
- Société suspendue: aucun accès portail, message neutre.

### Critères d'acceptation

1. Le cookie de session interne n'est jamais envoyé au domaine du portail, et un utilisateur du portail n'atteint aucune route interne (test).
2. Le test statique interdit au code du portail d'appeler tout service comptable hors liste blanche.
3. Pour **chaque** route du portail, un test généré à partir du fichier de routes vérifie qu'un objet hors du périmètre de l'utilisateur renvoie `404`.
4. Aucun accès à une page tant que le second facteur n'est pas configuré; aucune récupération par e-mail seul.
5. Une invitation est à usage unique, expire à 7 jours et n'est stockée que sous forme de hash.
6. Les sessions expirent à 30 minutes d'inactivité et 12 heures au plus; une validation de comptes exige un second facteur récent.
7. Une publication est immuable; la corriger crée une version; la retirer la cache sans la supprimer; le SHA-256 est enregistré et vérifié au téléchargement.
8. Une révocation prend effet à la requête suivante et invalide les sessions.
9. La revue des accès signale les droits inactifs et la suspension automatique s'applique.
10. Limitation de débit et verrouillage après échecs sont effectifs et testés.
11. Chaque action du portail figure dans R18 avec `actor_type = portal_user`, et l'écran d'activité l'affiche.
12. Aucun script ou ressource tiers n'est chargé par le portail (test de la politique de sécurité de contenu); une palette de couleurs sous le contraste AA est refusée.
13. Un **test d'intrusion externe** est réalisé avant l'ouverture à un premier client réel, et ses constats bloquants sont corrigés.

**Tests attendus**: suite d'accès direct à des identifiants générée depuis les routes, tests d'authentification et de sessions, tests d'invitation et de révocation, test statique de la liste blanche des services, tests de la politique de sécurité de contenu, tests de limitation de débit, tests de publication (immuabilité, version, retrait), Brakeman sans alerte, revue de configuration du rôle de base de données.

## 11. P2 · B02b Dépôt de pièces (mobile, réseaux instables)

**Objectif.** Permettre au client de déposer une pièce en quelques secondes depuis son téléphone, même sur un réseau lent ou intermittent, de voir où elle en est, et de justifier les opérations bancaires que le cabinet lui demande. Les pièces arrivent dans la boîte de réception de F03, par le même pipeline que toute pièce reçue.

### Écran d'accueil (mobile d'abord)

Quatre actions en grands boutons: **Photographier un document**, **Choisir un fichier**, **Envoyer par e-mail** (adresse dédiée de la société, avec QR code), **Pièces demandées**. Application web installable, utilisable sur un téléphone d'entrée de gamme; poids initial du JavaScript inférieur à 200 Ko.

### Capture par photo

- **Plusieurs pages** en une seule pièce: le client prend plusieurs photos, réordonne, tourne ou supprime, puis envoie. Le serveur assemble un seul PDF.
- **Aide à la qualité, en local et non bloquante**: détection de photo floue ou trop sombre (mesures simples sur le canvas), avec un message « La photo est floue, la reprendre ? ». Le client peut passer outre.
- **Compression côté client**: JPEG de qualité 80 et 2 000 pixels au plus sur le grand côté, plus une réduction automatique en **mode économie de données** quand le débit mesuré est faible.
- Côté serveur: rotation automatique selon les métadonnées EXIF, conversion des formats de téléphone (HEIC vers JPEG), assemblage du PDF avec libvips ou équivalent.

### Envoi robuste

- **Envoi par morceaux reprenable**: `upload_sessions` (identifiant, utilisateur, taille, empreinte SHA-256 attendue, plages reçues, expiration à 48 heures). Morceaux de 1 Mo, envoyés avec leur position et leur somme de contrôle; l'état d'une session se relit pour reprendre exactement où l'envoi s'est arrêté. Un morceau rejoué est sans effet (idempotence). L'agent de codage évalue d'abord un protocole existant (de type tus) avant d'écrire le sien.
- **File d'attente hors ligne**: si le réseau est absent, les documents sont conservés localement (service worker et IndexedDB) et envoyés au retour de la connexion, avec reprises et attente croissante. L'écran affiche « 3 en attente d'envoi » et ne marque un document « envoyé » qu'à l'accusé du serveur.
- Sur les navigateurs sans synchronisation en arrière-plan, l'envoi reprend à l'ouverture suivante et un rappel s'affiche.
- **Confidentialité locale**: option « effacer les envois en attente à la déconnexion » (recommandée sur un appareil partagé); expiration de la file au bout de 30 jours, avec avertissement.

### Réception côté serveur

1. Les fichiers arrivent d'abord en **quarantaine**. Contrôle du type réel par le contenu, de la taille, du nombre de pages, analyse antivirus, protection contre les images de dimensions démesurées (100 mégapixels au plus).
2. **Assainissement des PDF**: suppression des scripts, des actions et des fichiers intégrés, ou remise à plat du document.
3. Détection de doublon (SHA-256 et quasi-doublon, F03).
4. Création du document F03 avec `source = portal` et l'identité du déposant. Il n'est **jamais** analysé par un modèle sans action explicite de l'équipe (règle d'A09).
5. **Reçu immédiat**: identifiant, horodatage, nom du fichier, début de l'empreinte. Liste « Mes envois » visible du seul déposant.

Formats acceptés: PDF, JPEG, PNG, HEIC, TIFF, XLSX et CSV. Un fichier protégé par mot de passe est accepté et marqué « À compléter ».

### Ce que le client indique, et ce qu'il ne décide pas

- Type: Achat (défaut), Vente, Note de frais, Relevé, Autre; note libre de 300 caractères.
- Ces informations sont des **indications non fiables** (`portal_hint`). C'est l'équipe du cabinet qui classe et comptabilise. Le client ne choisit jamais un compte ni un traitement.

### Statuts visibles par le client

| Statut client | Origine interne (F03, F08) |
| --- | --- |
| Reçu | Document en boîte de réception |
| En cours de traitement | Pris en charge, extraction ou codage en cours |
| Comptabilisé | Lié à une écriture validée |
| À compléter | Question ouverte (F08) ou fichier inexploitable |
| Refusé | Rejeté avec un motif prédéfini (illisible, doublon, hors comptabilité) |

Aucun détail comptable n'est montré. Un passage à « À compléter » notifie le client.

### Pièces demandées

- Le cabinet sélectionne dans F02 des lignes de relevé sans pièce et clique « Demander les justificatifs ». Cela crée une `document_request` (lignes, message, échéance) publiée dans le portail, avec rappels.
- Le client voit, pour chaque ligne, des **champs limités**: date, libellé nettoyé, montant. Jamais l'IBAN de la contrepartie ni de données bancaires détaillées. Le réglage `portal_show_bank_lines` peut désactiver cet affichage; par défaut il est réservé aux rôles Dirigeant et Collaborateur.
- Le client peut: **joindre une pièce** (envoi lié directement à la ligne), ou **répondre sans pièce** avec un motif prédéfini (« pas de facture, dépense personnelle », « pièce perdue, copie demandée », « autre » avec note). Ces réponses créent une tâche pour le comptable. **Rien n'est comptabilisé automatiquement.**

### Adresse e-mail dédiée

Les e-mails reçus par F03 (ActionMailbox) ne sont acceptés que depuis les adresses des utilisateurs du portail de la société et des extras configurés. Les autres vont en quarantaine pour revue interne. Contrôles SPF et DKIM à l'entrée. Un accusé de réception automatique indique un nombre de pièces, sans contenu.

### Quotas et protection contre les abus

200 fichiers par jour et par utilisateur, 2 Go par mois et par société (paramétrables), 100 pages par PDF, 25 Mo par fichier après compression, 20 fichiers par action. Limitation de débit par utilisateur et par adresse.

### Sécurité

- Toute pièce est **non fiable**: quarantaine, assainissement, jamais exécutée, jamais visible d'un autre client.
- Les miniatures ne sont visibles que du déposant.
- Aucune donnée d'une société n'apparaît sous une autre: la société courante est affichée en permanence en tête d'écran quand un client en gère plusieurs, et un document envoyé à la mauvaise société peut être déplacé par l'équipe.
- Journalisation dans R18 de chaque dépôt, refus et réponse.

### Indicateurs

Délai entre un mouvement bancaire et le dépôt de sa pièce, taux de pièces « À compléter », taux de justificatifs fournis dans le délai, part des pièces arrivées par le portail plutôt que par e-mail.

### Cas limites

- Coupure pendant un morceau: reprise à la position exacte, sans doublon.
- Même fichier envoyé deux fois: un seul document, avec un message clair.
- Horloge du téléphone fausse: seule l'heure du serveur fait foi.
- Photo HEIC ou très grande: convertie et réduite côté serveur si le client ne l'a pas fait.
- Client hors ligne plusieurs jours: la file est conservée, avec rappel et expiration à 30 jours.
- Espace de stockage du navigateur insuffisant: le client est prévenu et invité à envoyer d'abord les pièces en attente.
- Justificatif demandé alors que la ligne a déjà été justifiée par l'équipe: la demande est retirée automatiquement, avec message.

### Critères d'acceptation

1. Un envoi coupé à mi-parcours reprend exactement à la bonne position, avec un fichier final identique à l'original (SHA-256 égal), sous perte de morceaux simulée.
2. Rejouer plusieurs fois le même morceau ou la même session ne crée aucun doublon.
3. Hors ligne, un document est conservé et s'envoie tout seul au retour du réseau, et n'est marqué « envoyé » qu'après l'accusé du serveur.
4. Plusieurs photos deviennent un seul PDF dans l'ordre choisi, avec rotation EXIF correcte; un fichier HEIC est converti.
5. Un fichier de test antivirus, un PDF avec script, une image de 200 mégapixels et un type falsifié sont refusés ou neutralisés, et rien ne s'exécute.
6. Un e-mail d'une adresse non autorisée va en quarantaine et n'entre pas dans la boîte de réception.
7. Le client ne voit que ses propres envois et, dans « Pièces demandées », uniquement les champs limités (jamais d'IBAN).
8. Une réponse « sans pièce » crée une tâche et ne modifie aucune écriture.
9. Les quotas et limites de débit s'appliquent avec un message clair.
10. La page d'accueil respecte le budget de poids (JavaScript initial sous 200 Ko) et passe un audit de performance et d'accessibilité sur un profil de téléphone d'entrée de gamme et de réseau lent.
11. Chaque dépôt figure dans R18 avec l'identité du déposant.

**Tests attendus**: tests d'envoi avec un proxy de chaos (coupures, latence, morceaux perdus ou dupliqués), tests hors ligne avec un navigateur automatisé, tests du pipeline d'images (HEIC, EXIF, flou), tests de sécurité des fichiers (EICAR, PDF piégés, bombes d'image), test de liste d'expéditeurs autorisés, suite d'accès direct à des identifiants, tests de quotas, mesures de performance sur profil mobile lent, contrôle d'accessibilité.

## 12. P2 · B02c Questions, validation des comptes et tableau de bord client

**Objectif.** Faire du portail un lieu de collaboration: le client répond aux questions du cabinet, valide les chiffres qui lui sont présentés avec une preuve solide, et suit sa situation sur un tableau de bord clair. Tout ce que le client voit vient de **publications** ou d'**instantanés** préparés par le cabinet (B02a).

### Questions au client (F08)

**Création côté cabinet.** Depuis une écriture, une ligne bancaire, une pièce ou une tâche F08 de type « question client ». Champs: titre en langage simple, contexte visible (aperçu de la pièce ou champs limités de la ligne), type de réponse, échéance.

- **Types de réponse**: texte libre, choix unique ou multiple, oui ou non, fichier, montant ou date.
- **Modèles** de questions fréquentes (`question_templates`, par langue): « Cette dépense est-elle professionnelle ? » (oui, non, partiellement avec un pourcentage), « À quoi correspond ce paiement ? », « Pouvez-vous fournir la facture ? ».
- L'agent (A11, type `client_request`) peut proposer la formulation; l'humain relit avant publication.

**Côté client.** `portal_questions` (société, tâche, contenu, réponses attendues, statut `open`, `answered`, `closed`, `expired`) et `portal_answers` (question, auteur, contenu, fichiers, date). La réponse devient un commentaire de la tâche F08 et notifie le cabinet.

- **Réponses rapides**: chaque choix peut porter un `suggested_treatment` (« professionnelle: comptabiliser en charge ») affiché au comptable comme **suggestion**. Aucun traitement n'est appliqué automatiquement.
- **Rappels** amicaux à J+3, J+7 et J+14 qui s'arrêtent à la réponse; regroupés en un seul résumé (« Vous avez 5 questions »), avec un plafond hebdomadaire par client et des heures calmes. Sans réponse, une tâche de suivi interne est créée.
- Les réponses sont des **textes non fiables**: assainis, limités en taille; les fichiers passent par le pipeline de B02b.

### Messages

Un fil simple par société (`portal_threads`, `portal_messages`), avec pièces jointes, notifications et conversion en tâche. Une mention rappelle qu'un message n'est pas une instruction comptable ni un accord formel. Limitation de débit et retention paramétrée.

### Validation des comptes

**Publication à valider.** Le cabinet publie une situation (par exemple R07 et R08, avec un commentaire et, en option, un certificat d'intégrité `standard` de B03c) avec `requires_approval = true` et désigne les personnes qui peuvent valider: des Dirigeants dont l'**identité est vérifiée** (B02a).

**Parcours du client.**

1. Lecture: visionneuse du PDF, résumé en langage simple, commentaire du cabinet. Les boutons de décision ne s'activent qu'après ouverture effective des documents (`viewed_at`).
2. Trois décisions: **Approuver**, **Approuver avec remarques** (texte obligatoire), **Refuser** (motif obligatoire).
3. Avant d'approuver: nouvelle authentification par second facteur, et une case de confirmation qui **liste les documents et leurs empreintes courtes**.

**Preuve (`client_approvals`).** Publication et **empreinte du manifeste de ses fichiers**, décision, commentaire, identité du déposant, date, adresse IP, empreinte de l'agent utilisateur, méthode et date du second facteur, et `evidence_hash` (SHA-256 de la preuve en JSON canonique). Cette preuve est **scellée** par la même infrastructure de signature que les certificats (B03c, Ed25519), ce qui la rend infalsifiable sans qu'on s'en aperçoive. Le cabinet télécharge un PDF « Preuve d'approbation ».

**Liée à une version.** Une nouvelle version d'une publication marque les approbations précédentes `superseded` et invite le client à valider à nouveau. On ne peut jamais approuver un contenu que le client n'a pas vu.

**Effets.** Notification au cabinet. Sur option (`client_approval_required`), l'étape 18 « Approbation » de la clôture (F10) exige cette validation. Plusieurs Dirigeants: la politique `approvals_required` choisit entre un seul et tous.

**Portée juridique.** La validation par le client **n'est ni une signature électronique qualifiée, ni l'approbation des comptes annuels par l'organe compétent**. Le texte affiché au client le précise et sa formulation exacte est relue par un juriste (question consignée dans `QUESTIONS.md`). Une interface `SignatureProvider` permet plus tard de brancher un prestataire de signature qualifiée, hors périmètre ici.

### Tableau de bord client

- **Instantanés** `portal_snapshots`: société, période, indicateurs en JSON, date de génération, `known_at` source, SHA-256, option d'**approbation par le cabinet avant publication**. Un job les génère chaque nuit et à chaque publication à partir des services internes, avec une **liste blanche** d'indicateurs. Le client ne déclenche jamais un calcul.
- **Indicateurs**: trésorerie disponible, ventes du mois contre le mois précédent et l'an dernier, résultat cumulé, créances clients échues (montant et nombre), dettes fournisseurs à payer dans les 30 jours, lignes de budget au-delà de 90 % (option). Chaque carte affiche sa date de mise à jour et la mention « données provisoires » tant que la période n'est pas clôturée, une petite courbe des 12 derniers mois et une infobulle en langage simple (« Créances échues: factures clients en retard de paiement »).
- **Graphiques** avec les composants communs du §17 de la spécification des rapports, chacun avec son tableau alternatif accessible.
- **« Le mot du comptable »**: commentaire du mois, rédigé avec l'aide de l'agent (A11, type `summary`) et **relu et validé par l'humain** avant publication.
- **Confidentialité par défaut**: pas de noms de tiers (`portal_show_partner_names` désactivé); les indicateurs concernent la société seule.
- **Alertes** définies par le cabinet, par exemple une trésorerie prévisionnelle (R14) sous un seuil, notifiées au Dirigeant.
- Export PDF du tableau de bord.

### Espace du cabinet

Écran « Portail »: pièces reçues récemment, questions en attente par client et par ancienneté, publications et statut de leurs validations, activité, clients inactifs. Indicateurs: délai moyen de réponse d'un client, part des réponses sous sept jours, taux de justificatifs fournis dans le délai.

### Langage, accessibilité et notifications

Français, néerlandais et anglais; vocabulaire simple, sans jargon comptable non expliqué; conformité WCAG AA; fuseaux horaires affichés. Un résumé hebdomadaire par e-mail (compteurs et liens), notifications push web facultatives, heures calmes.

### Cas limites

- Question posée sur une écriture modifiée depuis: le contexte affiché est celui de la question, avec mention « mis à jour ».
- Réponse arrivée après la clôture de la période: enregistrée, signalée à l'équipe, sans effet comptable.
- Approbation d'une publication retirée entre l'ouverture et la décision: refusée avec un message clair.
- Dirigeant remplacé pendant une validation: les approbations en cours sont réévaluées, le nouveau Dirigeant doit être vérifié.
- Publication avec certificat: la validité du certificat est revérifiée à l'affichage.
- Deux Dirigeants en désaccord (un approuve, un refuse): la publication reste en attente, le cabinet est alerté.
- Client à plusieurs sociétés: les questions, publications et tableaux de bord restent strictement séparés.

### Critères d'acceptation

1. Une réponse à une question crée le commentaire de la tâche F08 et notifie le cabinet, sans modifier aucune écriture.
2. Un choix rapide affiche sa suggestion au comptable et ne déclenche aucun traitement.
3. Les rappels s'arrêtent à la réponse et respectent le plafond hebdomadaire et les heures calmes.
4. Un client ne peut pas approuver avant d'avoir ouvert les documents, et l'approbation exige un second facteur récent.
5. La preuve d'approbation contient l'empreinte du manifeste des fichiers et une signature qui se vérifie; la modifier la rend invalide.
6. Republier une version invalide les approbations précédentes et invite à valider à nouveau.
7. Un utilisateur non Dirigeant ou dont l'identité n'est pas vérifiée ne peut pas valider les comptes.
8. Avec `client_approval_required`, l'étape 18 de F10 reste bloquée tant que la validation n'existe pas.
9. Le tableau de bord ne contient que des indicateurs de la liste blanche, sans nom de tiers par défaut, et se génère sans action du client.
10. Chaque graphique du tableau de bord a son tableau alternatif et son texte alternatif en fr, nl et en.
11. Un texte du « mot du comptable » rédigé par l'agent n'est publié qu'après validation humaine.
12. Le texte de validation et son avertissement de portée juridique sont affichés au client et consignés avec la preuve.

**Tests attendus**: specs des questions (création, réponses par type, rappels avec `travel_to`, plafond), spec de non-application des suggestions, specs du parcours de validation (ouverture obligatoire, second facteur, version, désaccord), spec de scellement et de vérification de la preuve, specs de la liste blanche des indicateurs, suite d'accès direct à des identifiants sur toutes les routes, specs d'accessibilité et de langues, spec système du parcours complet: question, réponse, publication, validation.

## 13. Stratégie de tests et définition de « terminé »

Ces capacités manipulent de l'argent, prétendent prouver le passé et ouvrent le système à des tiers. Les risques dominants sont donc: un paiement sans approbation ou en double, un fichier de paiement altérable, une reconstruction historique infidèle, une preuve invérifiable, et un accès externe hors périmètre. La stratégie vise d'abord ces cinq risques.

### Jeu de données

On reprend le jeu de référence des trois spécifications précédentes et on y ajoute:

| Axe | Ajouts |
| --- | --- |
| B01 | Politiques d'approbation (seuils, premier paiement, projet), délégations, 12 fournisseurs dont 3 avec IBAN modifié ou erroné, factures variées (notes de crédit, paiements partiels, litiges), fichiers CODA de deux banques en lignes groupées et détaillées, lot partiel, retour de virement, double paiement |
| B03a et B03b | Séquences d'opérations horodatées avec instantanés à des instants aléatoires, exercice clôturé, TVA déposée, rapprochements figés, écritures tardives, comptes renommés, fenêtres de déverrouillage, écritures importées |
| B03c | Vecteurs de test de la canonicalisation et de l'arbre de Merkle, paquets intacts et paquets altérés (au moins 20 types d'altérations), autorité d'horodatage de test, clés de test |
| B02 | Trois sociétés, cinq utilisateurs du portail dont un présent dans deux sociétés, corpus de fichiers hostiles (fichier de test antivirus, PDF piégés, images démesurées, types falsifiés, HEIC, gros scans), proxy de chaos, profil d'appareil mobile lent |

Comme pour les spécifications précédentes, les valeurs attendues sont **calculées indépendamment** du code testé et figées dans `spec/fixtures/reference_ledger/expected/`.

### Niveaux de tests

- **Séquences aléatoires**: le test de propriétés existant est étendu aux approbations, lots, confirmations, retours, extournes, verrouillages et validations. Après chaque suite, les invariants I1 à I15 tiennent, aucune facture n'est payée deux fois, et les vues `known_at` reproduisent les instantanés enregistrés en cours de route.
- **Droits**: les nouvelles lignes de `Permissions::MATRIX` (§2.2) sont parcourues par l'interface **et** par l'API.
- **Sécurité du portail**: suite d'accès direct à des identifiants **générée à partir du fichier de routes** (chaque route, un objet d'un autre périmètre, réponse `404`), tests statiques de liste blanche des services, de politique de sécurité de contenu, de sessions, d'expiration, de second facteur obligatoire, de limitation de débit et de verrouillage.
- **Secrets et données bancaires**: tests qui échouent si le schéma contient un identifiant bancaire de l'utilisateur, si une clé privée apparaît dans le dépôt, les journaux ou une sauvegarde non chiffrée, ou si un IBAN complet est journalisé.
- **Concurrence**: même facture dans deux lots, approbations simultanées, deux confirmations du même paiement, validations simultanées de plusieurs processus (monotonie de `posted_seq`), morceaux d'envoi rejoués.
- **Déterminisme**: fichier de paiement identique octet pour octet, empreintes et certificats reproductibles, résultats historiques mis en cache identiques à leur recalcul.
- **Vérification indépendante**: `ledger-verify` s'exécute en intégration continue dans un **conteneur vierge sans l'application**, sur les paquets intacts (`PASS`) et sur les paquets altérés (chaque altération donne `FAIL` avec la cause exacte).
- **Réseau**: envois avec proxy de chaos (coupures, pertes, doublons de morceaux), file hors ligne avec un navigateur automatisé.
- **Système** (Capybara ou équivalent), deux parcours complets: **(1)** facture Peppol, bon à payer, lot, export, débit CODA, confirmation, lettrage, certificat, vue historique; **(2)** invitation au portail, second facteur, dépôt hors ligne, question, réponse, publication, validation par le client.
- **Performance**: liste « À approuver » de 500 éléments en moins de 500 ms; contrôle préalable d'un lot de 500 paiements en moins de 5 s; fichier de 5 000 paiements en moins de 10 s; vues historiques à moins de 20 % au-dessus du courant; R21 sur 10 000 changements en moins de 3 s; certificat sur 500 000 écritures en tâche de fond en moins de 15 min; pages du portail utilisables en moins de 5 s sur le profil mobile lent.
- **Mutation** (Mutant): moteur d'approbation, règles d'éligibilité, contrôles préalables, contrôle de somme du fichier, canonicalisation, arbre de Merkle, `WitnessCheck`, portée du portail.
- **Qualité**: RuboCop, Brakeman, Bullet, `bundler-audit`, `i18n-tasks` (fr, nl, en), accessibilité automatisée, détection de secrets.

### Revues externes

Deux revues sortent du cadre de l'agent de codage et conditionnent l'ouverture:

1. **Revue de la conception cryptographique** de B03c (canonicalisation, Merkle, chaînage, signatures, gestion des clés) par un relecteur indépendant, avant la première émission d'un certificat destiné à un tiers.
2. **Test d'intrusion externe** du portail (B02a) avant l'ouverture à un premier client réel.

### Déploiement progressif

1. **B01**: dossier de démonstration, puis un ou deux dossiers réels. Les premiers lots ne contiennent **qu'un seul paiement de faible montant**, comparé à la banque; puis des lots réduits; puis l'usage normal. Revue de chaque lot pendant un mois.
2. **B03**: activation interne, comparaison des témoins pendant deux semaines, puis émission des premiers certificats après la revue cryptographique.
3. **B02**: un client pilote, après le test d'intrusion, avec le niveau de détail le plus restreint.

Chaque étape est derrière un drapeau de société (`feature_b01a` à `feature_b02c`). Une capacité ne passe à l'étape suivante que si ses critères de qualité et de sécurité sont tenus sur la période.

### Définition de « terminé » pour chaque capacité

- [ ] Tous les tests de la capacité passent; couverture SimpleCov d'au moins 95 % sur son dossier.
- [ ] Score de mutation d'au moins 85 % sur les composants listés ci-dessus qui la concernent.
- [ ] Les invariants I1 à I15 sont verts, y compris après une séquence aléatoire d'opérations.
- [ ] Chaque action est couverte par la matrice de droits et testée par l'interface et par l'API.
- [ ] L'isolation entre sociétés est testée; pour le portail, la suite d'accès direct à des identifiants passe sur toutes les routes.
- [ ] Idempotence et concurrence testées pour tout traitement de fond, import, envoi ou validation.
- [ ] Aucune donnée bancaire de l'utilisateur, clé privée ou IBAN complet dans le schéma, les journaux ou le dépôt.
- [ ] Aucune écriture validée sans action humaine, sauf les exceptions listées dans la section (lettrage exact des paiements).
- [ ] Toute action est journalisée dans R18, avec l'acteur, le motif quand il est exigé, et le type d'acteur.
- [ ] Budgets de performance tenus.
- [ ] Libellés en fr, nl et en; états vides, chargement et erreurs traités; accessibilité vérifiée.
- [ ] Capacité livrée derrière son drapeau et documentée dans `docs/signature/Bxx.md` (usage, règles, limites).
- [ ] Le compte rendu de l'agent de codage liste ses hypothèses, ses écarts avec cette spécification et les questions à valider par un comptable, un juriste, la banque de l'utilisateur ou un relecteur de sécurité dans `QUESTIONS.md`.

## 14. Prompts prêts à l'emploi pour Claude Code

Enregistrez ce document dans le dépôt sous `docs/signature/SPEC.md`, à côté des trois autres spécifications. Les prompts s'y réfèrent par leurs numéros de section. Donnez-les un par un, dans l'ordre, et validez le résultat de chacun avant de passer au suivant.

### 14.1 Règles permanentes (à ajouter à `CLAUDE.md`)

```text
Fonctions signature — règles de travail
- Les sources de vérité sont docs/signature/SPEC.md, docs/agent/SPEC.md, docs/features/SPEC.md et docs/reports/SPEC.md. En cas de doute, les relire; ne pas deviner.
- TDD strict: test rouge, code minimal, test vert, refactoring. Un commit par étape cohérente.
- Une capacité à la fois. Ne pas commencer la suivante tant que la définition de « terminé » (§13) n'est pas remplie.
- LedgerFlow ne stocke jamais d'identifiant de connexion bancaire de l'utilisateur et n'initie jamais de paiement. Il produit un fichier que l'humain autorise dans sa banque.
- Toute écriture comptable passe par Ledger::PostEntry, ReverseEntry, Reconcile ou Unreconcile. Les seules validations automatiques autorisées sont les exceptions listées dans la section de la capacité.
- Un fichier de paiement exporté est immuable. Le générer deux fois doit donner le même fichier octet pour octet.
- Le code du portail (Portal::) n'appelle jamais de service comptable ni de rapport. Il ne lit que les tables et vues portal_*. Tout identifiant exposé à un externe est un jeton opaque, et toute lecture passe par la portée du droit de l'utilisateur.
- Tout ce qui vient d'un externe (pièces, réponses, messages, e-mails) est non fiable: quarantaine, assainissement, jamais exécuté, jamais validé automatiquement.
- Cryptographie: bibliothèques standard uniquement (OpenSSL, bibliothèque standard de Ruby). Aucune primitive maison. Canonicalisation selon RFC 8785 avec vecteurs de test. Aucune clé privée dans le dépôt, la base ou les journaux.
- Aucune version de format bancaire, aucune particularité de banque, aucun texte juridique n'est supposé: les obtenir dans la documentation ou auprès de l'utilisateur, sinon appliquer le comportement le plus prudent et l'inscrire dans docs/signature/QUESTIONS.md.
- Chaque capacité est livrée derrière un drapeau de société, avec audit R18 de chaque action et type d'acteur.
- Ne jamais supprimer ou affaiblir un test pour le faire passer.
```

### 14.2 Prompt d'audit (à donner en premier, sans coder)

```text
Lis intégralement docs/signature/SPEC.md et les trois autres spécifications. Ne modifie aucun fichier de code.

Audite ensuite le dépôt et produis docs/signature/00-audit.md contenant:
1. L'état réel de ce dont ces capacités dépendent: F01 (droits, périodes verrouillées, second facteur), F02 (règles de rapprochement CODA), F03 (pièces, boîte de réception), F04, F06, F07, F08, R14, R18 (chaîne d'audit et sa définition exacte du hachage), R19.
2. L'existant utile: un éventuel client mobile d'approbation, l'authentification multi-modèles, les services de génération de PDF et d'export, la file de jobs, le stockage de fichiers, l'analyse antivirus, la gestion des secrets.
3. Pour B03a: où et comment posted_at est fixé aujourd'hui, si un ordre monotone par société est garanti, quels champs peuvent encore être modifiés après validation, et l'état des données de référence versionnées.
4. Pour B03c: le format exact des événements d'audit, ce que la migration vers la version 2 de la chaîne exige, et les risques.
5. Pour B02: l'infrastructure disponible pour un sous-domaine séparé, le TLS, un rôle de base de données restreint, et la faisabilité d'une application web installable avec envoi hors ligne.
6. Les décisions qui demandent mon avis, avec options et conséquences: banques à supporter et fichiers d'exemple à me demander, versions du format de virement, autorité d'horodatage, gestion des clés de signature, prestataire d'envoi d'e-mails, domaine du portail.
7. Les points du SPEC ambigus, contradictoires ou incompatibles avec le code existant.
8. Un plan détaillé de la vague P0, tâche par tâche, avec l'ordre des commits.

Arrête-toi après avoir écrit ce fichier et attends ma validation.
```

### 14.3 Prompt générique d'une capacité

```text
Implémente la capacité Bxx décrite dans la section §N de docs/signature/SPEC.md, en suivant docs/signature/00-audit.md.

Procède en TDD dans cet ordre:
1. Les jeux de données de référence et les résultats attendus indépendants de la capacité (§13).
2. Les specs des services, des policies et des contrôles, y compris les cas limites, la concurrence et l'isolation.
3. Les migrations réversibles, les modèles, les services et les jobs.
4. Les contrôleurs, les endpoints d'API, les composants et les écrans.
5. La matrice de droits (§2.2), l'audit R18 avec le type d'acteur, et le drapeau feature_bxx.
6. Les invariants I1 à I15 (dont les séquences aléatoires) et les contrôles de sécurité de la section.
7. Les traductions fr, nl, en, l'accessibilité et docs/signature/Bxx.md.

Vérifie chaque critère d'acceptation de la section un par un, en citant le test qui le couvre. Ne passe pas à la capacité suivante. Termine par un compte rendu: critères couverts, écarts avec le SPEC, questions ajoutées à QUESTIONS.md.
```

### 14.4 Prompts par vague

**P0**

```text
Implémente dans cet ordre, en appliquant le prompt générique 14.3 à chacune: B01a (§4), B01b (§5), B01c (§6). Avant B01b, demande-moi les banques à supporter et des fichiers CODA réels anonymisés de chacune, ainsi que la documentation du format de virement de ces banques; n'invente aucune particularité. Après chaque capacité, arrête-toi et présente le compte rendu. À la fin de la vague, vérifie les critères de sortie de P0 du §3 et exécute le parcours système complet: facture, bon à payer, lot, export, débit, confirmation, lettrage.
```

**P1**

```text
Implémente B03a (§7), puis B03b (§8), puis B03c (§9). Avant B03c, présente-moi les options d'autorité d'horodatage et de gestion des clés avec leurs coûts et leurs conséquences, et attends ma décision. Propose la migration de la chaîne d'audit vers la version 2 sans modifier aucun événement existant. Écris ledger-verify comme un outil autonome, sans dépendance à Rails, et exécute-le en intégration continue dans un conteneur vierge. Vérifie les critères de sortie de P1 du §3. N'émets aucun certificat destiné à un tiers avant la revue cryptographique décrite au §13.
```

**P2**

```text
Implémente B02a (§10), puis B02b (§11), puis B02c (§12). Commence B02a par l'isolation (origine, identité, code, base de données) et par la suite d'accès direct à des identifiants générée depuis les routes, avant toute fonctionnalité. Pour le texte de validation des comptes, n'invente aucune formulation juridique: prépare-la et consigne-la dans QUESTIONS.md pour relecture par un juriste. N'ouvre le portail à aucun client réel avant le test d'intrusion décrit au §13. Vérifie les critères de sortie de P2 du §3.
```

### 14.5 Prompt de revue de fin de vague

```text
Fais une revue critique de la vague P<n>, comme le ferait un auditeur de sécurité et un expert-comptable qui n'ont pas vu le code.

1. Relis les sections du SPEC de la vague et compare-les au code livré, critère par critère.
2. Exécute la suite complète, les séquences aléatoires d'invariants, les tests de concurrence, les tests de chaos réseau, ledger-verify sur les paquets intacts et altérés, et les tests de performance.
3. Cherche activement: un chemin qui permet de payer sans approbation, un IBAN utilisable sans vérification, un fichier de paiement modifiable après export, une écriture validée par un traitement automatique hors exceptions, un posted_at modifiable ou non monotone, un certificat qui affirme plus qu'il ne prouve, une clé ou un secret dans le dépôt ou les journaux, une route du portail qui accepte un identifiant hors périmètre, un appel du portail vers un service comptable, un contenu externe traité comme une instruction.
4. Vérifie l'audit R18 de chaque action et l'absence de données sensibles dans les journaux.
5. Liste tout écart, même mineur, avec le fichier, la ligne et le test qui manque.

Ne corrige rien tant que je n'ai pas validé la liste.
```

### 14.6 Prompt de préparation des revues externes

```text
Prépare le dossier de la revue externe demandée au §13: pour la cryptographie de B03c, docs/signature/CRYPTO_REVIEW.md (objectifs de sécurité, menaces, canonicalisation, arbre de Merkle, chaînage des ancrages, signatures, gestion et rotation des clés, horodatage, limites connues, vecteurs de test, code concerné); pour le portail, docs/signature/PENTEST_SCOPE.md (périmètre, environnements de test, comptes de test, objets sensibles, hypothèses, ce qui est exclu). N'active ni certificat ni portail sur des données réelles sans mon accord explicite.
```

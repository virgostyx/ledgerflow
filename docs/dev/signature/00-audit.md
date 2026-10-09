# Audit — Fonctions signature B01 à B03 (§14.2)

Réalisé à partir de `docs/dev/signature/spec.md` (lu intégralement), de `CLAUDE.md`, de `docs/dev/HANDOFF_next_steps.md` et d'une exploration du dépôt (branche `development`, commit `f448dba`). **Aucun fichier de code n'a été modifié.** Je n'ai pas lancé la suite de tests : les constats viennent de la lecture du code et de `db/structure.sql`. Ce que je n'ai pas pu confirmer est marqué « à confirmer ».

## 0. Lecture rapide

- Le dépôt est **très en avance sur les hypothèses de la spec** (F01 à F13 et A01 à A12 livrés). Les quatre dépendances difficiles de B03 existent : verrous de période en SQL, chaîne d'audit hachée, intégrité des documents, témoins figés. Ce qui manque, c'est surtout de quoi **dater et ordonner** (`posted_at`, `posted_seq`) et de quoi **prouver** (empreinte de contenu, ancrage, signature).
- **Le module Payments existant entre en conflit direct avec B01b/B01c** (§2). Il crée l'écriture de règlement à l'« exécution » du lot, avant tout débit bancaire; il lit l'IBAN sur le tiers sans vérification; son fichier n'est pas déterministe. Il faut le **remplacer, pas l'étendre**.
- **Collisions de numérotation** : la spec crée un invariant I12 à I15 et un contrôle C18/C19, mais `spec/invariants/` contient déjà I1 à I13 (I12 = devises, I13 = imports/API), et `c18_document_integrity.rb` existe déjà. À renuméroter avant d'écrire du code (§7, points 1 et 2).
- **Pas de nl** : `config/locales` ne contient que `en.yml` et `fr.yml`. La spec exige fr, nl et en. Le même arbitrage a été fait pour F (interface en anglais, règle du projet). À reconfirmer (§6, décision 9).
- **Pas d'« authentification multi-modèles »** au sens de la spec : il y a `User` (Devise, passkeys WebAuthn, TOTP, codes de secours) et `ApiClient` (clé hachée, scopes). Un `PortalUser` serait un second modèle Devise neuf.
- **Aucun client mobile d'approbation dans ce dépôt.** BudgetFlow est un projet séparé (`docs/dev/api/budgetflow-adapter.md`) et je n'y ai trouvé aucune notion d'approbation. À ne pas toucher sans accord (CLAUDE.md).

## 1. État réel des dépendances

Légende : ✅ existe · 🟡 partiel ou sous une autre forme · ❌ absent.

| Dépendance | État | Constat |
|---|---|---|
| **F01 droits** | ✅ | `Permissions::MATRIX` (`app/policies/permissions.rb`), rôles par société `admin/accountant/assistant/manager/auditor` + `CustomRole`. Lecteur = `manager`, propriétaire = `admin` (même correspondance que F). Les nouvelles lignes de §2.2 se glissent telle quelle dans la matrice. `Permissions.allowed?` lève sur une permission inconnue (bien). |
| Périodes verrouillées | ✅ | `Accounting::PeriodLock` (accounting, vat, fiscal_year; déverrouillage temporaire avec `relock_at`) et deux triggers SQL (`enforce_period_lock_on_entries/lines`) avec une variable de session `ledgerflow.lock_override`. |
| Quatre yeux | ✅ | `Accounting::Actions::ValidateFourEyes` dans `PostJournalEntry`; `journal_entries.created_by_id` existe. |
| Second facteur | 🟡 | TOTP (`users.totp_secret`, chiffré) ou passkey; `second_factor_passed?` est un **booléen de session** (`session[:second_factor_user_id]`), sans horodatage. **Pas de « second facteur récent »**, que B01a (seuil), B01b (export), B02a et B02c exigent. À construire. |
| **F02 CODA** | ✅ | `Banking::Coda::Parser`, `Banking::ImportStatements`, `Banking::AutoMatch` (score minimal 75, 100 = exact, ne comptabilise en brouillon que les factures **clients** exactes), `Accounting::MatchBankTransaction`. Fixtures dans `spec/fixtures/files/coda/` (17 fichiers, **synthétiques**, générés par `generate.rb`). `bank_transactions` porte `counterparty_iban`, `structured_communication`, `bank_reference`, `fingerprint`, `match_data`. La « règle 0 » de B01c s'y ajoute comme une règle de `MatchBankTransaction`. |
| **F03 documents** | ✅ | `accounting_documents` (sha256, `legal_hold`, `retention_until`, `integrity_status`), `document_links`, boîte de réception, `DocumentsMailbox` (ActionMailbox, adresse secrète par société), `Accounting::VirusScan` (hook ClamAV par variable d'environnement, **désactivé par défaut**), `documents:verify`, contrôle C18 d'intégrité des pièces. Stockage Active Storage `:local`, **non chiffré au repos**. |
| **F04 lettrage** | ✅ | `Accounting::Lettering` (full/partial, `auto`, `reason`, `lettered_by_id`), `LetteringEvent` (par ligne, `action`, `created_at`), `AutoLetterExact`, `UnletterLines`. |
| **F06 Peppol** | ✅ | `Peppol::ReceiveInvoice`, `SupplierMatch`, `InvoiceChecks`. Les factures reçues créent un **brouillon d'achat**. À confirmer : si l'IBAN de la facture UBL est conservé (aucune colonne `iban` sur `accounting_invoices` : seulement `payment_reference`). |
| **F07 extourne** | ✅ | `Accounting::ReverseJournalEntry`, modèles d'écriture, écritures récurrentes. |
| **F08 tâches** | ✅ | `Accounting::Task` (kind, assignee, cible polymorphe, `anomaly_fingerprint`, `question`, `external_expires_at`), commentaires, notifications, **lien externe de réponse** (`/reply/...`, public, limité en débit par Rack::Attack). Ce lien est un précédent utile pour B02c, mais **n'est pas un portail**. |
| **R14** | ✅ | `Accounting::CashForecastQuery` : dettes fournisseurs prises à l'échéance, sans notion d'approbation ni de lot. À étendre pour séparer « approuvé » de « en attente » et compter les lots soumis à la date d'exécution. |
| **R18 audit** | ✅ | `Accounting::AuditLog.record!` : chaîne par société, verrou consultatif, SHA-256. Détails au §4. |
| **R19 contrôles** | ✅ | `Accounting::Consistency` avec C01 à C18 **non contigus** (C08, C10, C15 absents). Détail au §7. |
| **F10 clôture** | ✅ | 18 étapes; l'étape 18 `Closing::Steps::Approval` est manuelle et bloquante; `Closing::Approve`. L'étape 17 est `Closing::Steps::LockAndBundle` (verrou + liasse), conforme à la spec : le certificat s'y ajoute. |
| **API REST** | ✅ | `/api/v1/public/*` (clés `ApiClient` avec scopes). Pas d'endpoint d'approbation. |
| **Agent** | ✅ | `app/services/agent/tools/` : 27 outils de lecture/proposition. Les quatre outils §2.4 (`list_pending_approvals`, `get_payment_batch`, `get_changes_between`, `get_integrity_status`) sont à ajouter. Aucun outil n'écrit en comptabilité. |
| **Restriction par journal** | ✅ | `UserEntity#journal_ids` / `allows_journal?` (nil = tous). `time_travel.view` doit l'appliquer (critère 9 de B03a); à tester sur chaque rapport migré. |

## 2. Le module Payments existant face à B01b/B01c

Fichiers : `app/services/payments/*`, `app/models/accounting/payment_batch*.rb`, `PaymentBatchesController`, policy `payment_batch_policy.rb`, permission `payments.manage`.

| Point | Existant | Spec |
|---|---|---|
| Statuts du lot | `draft, generated, executed, cancelled` (AASM) | `draft, pending_approval, approved, exported, submitted, debited, partially_rejected, cancelled` (+ `cancel_requested`, cf. §7) |
| Écriture comptable | `CreateSettlementJournalEntry` crée **et valide** une écriture (440 / compte bancaire) à l'« exécution », **sans ligne de relevé**, à `Date.current`, avec `Accounting::FiscalYear.current` (bug connu, cf. mémoire) | Écriture en **brouillon à la confirmation du débit**, date du relevé, validation humaine par lot, lettrage exact ensuite |
| Facture | `MarkInvoicesPaid` : `invoice.pay!` à l'exécution | Facture `paid` seulement après lettrage |
| IBAN du tiers | `partner.iban` en clair, `Partner#sepa_payable?`, **aucune vérification ni période d'observation** | `partner_bank_accounts` avec statuts, deux personnes, 24 h, instantané par paiement |
| Fichier | gem `sepa_king 0.14.0`, `PAIN_001_001_03`, `message_id = SecureRandom.uuid` à chaque génération, `sepa_xml` stocké dans une colonne `text` du lot | Fichier **déterministe** octet pour octet, XSD, SHA-256, document F03 immuable, profil de banque |
| Approbation | aucune | Circuit `payment_batch` du moteur B01a |
| Paiement partiel / groupé | ligne = facture entière (`amount = total_incl_vat`) | `payment_item_invoices`, imputation partielle, notes de crédit |
| Droits | une seule permission `payments.manage` | `prepare/approve/export/confirm`, `bank_accounts.verify` |
| Simulateur | `Bank::Simulator::PayBatch` (dev/test) | à réécrire pour produire un débit CODA cohérent |

**Constat de fond.** `sepa_king` génère déjà un pain.001 valide; on peut le **garder comme moteur de sérialisation** derrière `Payments::Sepa::Pain001Builder` (le déterminisme s'obtient en fixant `message_identification` et `creation_date_time` à partir du lot, au lieu de laisser la gem les tirer au hasard). Il faut vérifier que la gem sait produire la version que la banque veut (§6, décision 2). Sinon, un builder Nokogiri maison plus un XSD.

**Données existantes.** Il reste peut-être des lots `executed` en production ou en démo avec des écritures déjà validées. Aucune donnée ne doit être modifiée sans accord : la migration doit **conserver** ces lots et leurs écritures, les marquer `legacy` (colonne ou statut à part) et les exclure des nouveaux contrôles. À vérifier sur la base réelle avant B01b.

## 3. Pour B03a : `posted_at`, ordre monotone, champs encore modifiables

- ❌ **Il n'existe ni `posted_at` ni `posted_seq`.** `journal_entries` a `locked_at` et `locked_by` (« system »), posés par `Actions::LockEntry` avec `Time.current` **côté Ruby**, et `updated_at`. `locked_at` n'est pas protégé par un trigger.
- ❌ L'ordre des écritures validées d'une société n'est pas garanti : `AssignSequenceNumber` numérote par journal, et aucun verrou consultatif ne couvre la validation. Les verrous consultatifs existants (`pg_advisory_xact_lock(hashtext('…'), entity_id)`) couvrent l'audit, les verrous de période, les suggestions de lettrage et l'import de relevés. **Le même schéma s'applique** à la validation (`PostJournalEntry`), mais cela sérialise toutes les validations d'une société : à mesurer (import de masse F13, validation par lot de B01c).
- 🟡 **Les écritures validées restent modifiables en SQL hors période verrouillée.** `enforce_period_lock_on_entries/lines` ne protège que les dates **dans une période verrouillée**; la protection hors verrou est au niveau modèle (`Accounting::Immutable`, callbacks Active Record), que `update_all` ou le SQL direct contournent. Pour B03a (« `posted_at` immuable, trigger »), il faut un **nouveau trigger** qui interdit toute modification des colonnes de contenu d'une écriture validée (et de ses lignes), en laissant passer les transitions légitimes : `posted → reversed`, lettrage et résiduel des lignes (déjà listés dans le trigger des lignes), et la fenêtre `ledgerflow.lock_override`.
- 🟡 **Lettrage daté** : `LetteringEvent` (par ligne, action, `created_at`) et `Lettering.lettered_on` permettent probablement de reconstruire les résiduels à un instant T. (a) **Confirmé** : `UnletterLines` fait `lettering.destroy!` : après un délettrage, l'état antérieur ne se reconstruit que par les `LetteringEvent`. À confirmer : (b) `amount_residual` sur les lignes est-il recalculable à T depuis les événements? Un test de propriété sera nécessaire avant de s'y fier (R04 à T, critère 4).
- ❌ **Données de référence versionnées** : aucune table `master_data_versions`. PaperTrail est présent (`gem "paper_trail"`); `versions` pourrait servir de source à la place d'une nouvelle table. À arbitrer (§6, décision 10) : PaperTrail est modifiable en SQL et sa granularité dépend des modèles qui l'incluent.
- ❌ `Reports::Filters` n'a pas de `known_at`; la vue `posted_lines` (statuts 1 et 2) n'expose pas `posted_seq`. Les rapports sont dans `app/queries/accounting/*` (R01 à R15 en classes `*_Query`) et non dans `app/reports/`, qui ne contient que `Filters`, `Period`, `Result` et les exporteurs. **Chaque requête devra recevoir `known_at`**, ce qui est un chantier large (≈ 25 classes).
- ❌ `history_start`, `user_visits`, `change_reviews` : à créer.
- ✅ Instantanés témoins : `closing_snapshots` (F10), `bank_reconciliation_reports` (immuable par trigger), déclarations TVA soumises, `consolidation_runs` (F12). Rien d'indépendant ne les recalcule aujourd'hui : `WitnessCheck` est neuf.
- Reprise F05 : **F05 est reportée** (mémoire projet). `import_batch_id` existe (F13a). Le cas `posted_at_source = import` concerne donc F13a (imports guidés) et non F05.

## 4. Pour B03c : chaîne d'audit et migration vers la version 2

**Format actuel** (`Accounting::AuditLog`) : table `accounting_audit_logs`, colonnes `auditable_type/id`, `action`, `user_id`, `user_email`, `payload jsonb`, `ip_address`, `user_agent`, `request_id`, `reason`, `entity_id`, `created_at`, `previous_hash`, `content_hash`.

```
content_hash = SHA-256( previous_hash ‖ JSON.generate(canonical({auditable_type, auditable_id, action,
                 user_id, user_email, payload, ip_address, reason, request_id, user_agent, entity_id,
                 created_at (iso8601, 6 décimales)})) )
```

- Une chaîne **par société**, verrou consultatif par société. Immuable par trigger (`prevent_audit_log_modification`). Vérification : `Accounting::AuditVerifier` et `rake audit:verify`.
- La sérialisation est un `JSON.generate` Ruby avec clés triées : **ce n'est pas du RFC 8785** (échappements, formes des nombres, ordre Unicode). Pour `ledger-verify` indépendant, soit on documente précisément cette canonicalisation, soit la v2 passe en JCS.
- `content_hash` **inclut le contenu** (adresse e-mail, IP, payload). Un tiers ne peut donc pas vérifier la chaîne sans lire ces données personnelles : c'est exactement ce que la v2 (`content_digest` séparé) doit corriger.

**Ce que la migration v2 exige**
1. Ajouter `content_digest` (SHA-256 du contenu seul), `chain_version` (1 ou 2) et `anchor_prev` sur les nouveaux événements; **ne rien recalculer sur les anciens** (le trigger l'interdit de toute façon).
2. Premier événement v2 = « événement de bascule » dont `previous_hash` est la tête v1 (ancrage de la v2 sur la v1, comme la spec le demande).
3. `AuditLog.digest` et `AuditVerifier` deviennent conscients de la version.
4. Les lignes **sans** `content_hash` (non chaînées : `where.not(content_hash: nil)` dans le code) sont ignorées par le vérificateur : à décompter et à signaler dans le certificat (réserve).
5. **Risque** : la chaîne actuelle écrit des lignes **hors tenant** pour les données de référence (`entity_id` nul) : elles ne sont dans aucune chaîne. À documenter sur le certificat.
6. **Risque** : `created_at` est arrondi à 6 décimales côté Ruby; `ledger-verify` devra reproduire exactement le format `iso8601(6)`.
7. Le `pg_advisory_xact_lock` de `record!` sert déjà de sérialisation; l'ancrage de Merkle peut s'appuyer sur `posted_seq` (B03a) plutôt que sur l'`id` de l'audit.

**Autres éléments pour B03c**
- OpenSSL 3.5.5 et `OpenSSL::PKey.generate_key("ED25519")` sont disponibles (Ruby 3.3.5) : signature Ed25519 et `openssl ts` pour RFC 3161 possibles **sans gem supplémentaire**, conformément à la règle « bibliothèques standard uniquement ».
- Gestion des secrets : `config/credentials.yml.enc` (Rails) et la variable `RAILS_MASTER_KEY` fournie par Kamal. Pas de KMS. Voir décision 5.
- Aucune gem de canonicalisation JSON n'est installée. JCS pour des valeurs en chaînes décimales et des entiers est faisable en quelques dizaines de lignes, avec vecteurs de test publics (RFC 8785 annexe B).
- `Accounting::ClosingBundle` / `Zipper` produisent déjà des archives ZIP avec manifeste : réutilisables pour le paquet de vérification.

## 5. Pour B02 : infrastructure

| Besoin | État |
|---|---|
| Sous-domaine séparé | ❌ Un seul hôte Kamal : `ledgerflow.budgetflowmanagement.com` (`proxy.host`, TLS auto par kamal-proxy). Kamal 2 accepte plusieurs hôtes (`hosts:`) sur le même conteneur; l'isolation de cookies passe par un hôte distinct (pas un domaine parent partagé). Un domaine personnalisé par cabinet demanderait un certificat par domaine (kamal-proxy le fait pour une liste d'hôtes déclarée, pas à la volée). |
| Routage par hôte | ❌ Aucun `constraints host`/`subdomain` dans `config/routes.rb`. À créer. |
| Rôle PostgreSQL restreint | ❌ Un seul utilisateur `ledgerflow` pour la base primaire; `config/database.yml` a quatre bases en production. Le portail peut ouvrir une **seconde connexion** (`connects_to`) avec un rôle limité aux tables `portal_*`. Cela demande de créer le rôle dans l'accessoire `db` (postgres:16-alpine) : à faire dans une migration ou un script d'initialisation. |
| Application web installable | 🟡 `app/views/pwa/manifest.json.erb` et `service-worker.js` existent (gabarits Rails, service worker vide) mais **aucune route ne les sert** (rien dans `config/routes.rb`). Pas de file hors ligne, pas d'IndexedDB. |
| Budget JavaScript < 200 Ko | 🟡 Importmap + Turbo + Stimulus + **echarts** (lourd). Le portail doit avoir un **layout et un importmap séparés** sans echarts. À mesurer. |
| Envoi par morceaux (tus ou équivalent) | ❌ Aucun gem ni protocole. Voir décision 8. |
| Traitement d'images | 🟡 `convert` (ImageMagick) est installé **sur cette machine**; ni `vips`, ni `ruby-vips`, ni `mini_magick` dans le `Gemfile`. À confirmer dans l'image Docker de production. HEIC demande `libheif`. |
| Antivirus | 🟡 Point d'entrée `VirusScan` prêt, **aucun ClamAV déployé** (pas d'accessoire Kamal). Mode « refuse si indisponible » par défaut dès qu'une commande est configurée. |
| E-mail sortant | ❌ **SMTP non configuré en production** (`production.rb` : « TODO: SMTP is not configured yet », `default_url_options` = `example.com`). SPF/DKIM/DMARC et domaine d'envoi sont un prérequis du portail et du résumé d'approbations. |
| Limitation de débit | ✅ Rack::Attack, mais avec un **cache mémoire par processus** (note du fichier : « en production, passer à un store partagé »). Un portail exposé exige un store partagé (Solid Cache) et des seuils par compte. |
| Sauvegarde du volume | 🟡 `ledgerflow_storage` : voir `docs/dev/backup_restore.md`. Les pièces déposées via le portail s'y ajouteront. |
| Chiffrement au repos | 🟡 `encrypts` sur secrets et données de l'agent; **pas** sur `partners.iban`, `bank_accounts.iban`, ni sur les pièces. La spec (B01b) exige IBAN et fichiers chiffrés au repos. |
| Journaux | 🟡 Masquage des IBAN : à vérifier avec `filter_parameters` et les `payload` d'audit (`Accounting::Iban` existe pour le format). |

## 6. Décisions qui demandent votre avis

1. **Banques à supporter et fichiers d'exemple.** Indiquez les banques utilisées par vos dossiers. Il me faut, pour chacune : (a) un CODA **réel anonymisé** d'un lot de virements SEPA (idéalement une ligne groupée *et* une version détaillée si la banque propose les deux), (b) la documentation de son format de virement. Aujourd'hui les 17 fichiers CODA du dépôt sont **synthétiques**, donc la règle 0 ne peut pas être validée à 90 % sur du réel.
2. **Version du format de virement.** Actuel : `pain.001.001.03` (gem). Les banques belges acceptent selon les cas `.03` ou une version plus récente (`.09`). Option A : rester en `.03` tant que votre banque l'accepte (aucun risque de refus, la gem suffit). Option B : viser `.09` (nécessite un builder maison + XSD). **Recommandation : A pour la première banque, avec le profil de banque prêt pour B.**
3. **Autorité d'horodatage RFC 3161.** Options : (a) aucune au départ (le certificat le dit, preuve = clé de l'instance seule); (b) service gratuit non qualifié (sans poids eIDAS); (c) prestataire qualifié eIDAS (poids juridique, coût à l'usage ou à l'abonnement). **Recommandation : (a) pour livrer, puis (c) avant le premier certificat destiné à un tiers.** À décider avant B03c.
4. **Ancrage rétroactif à l'activation.** Il couvre l'historique existant d'un seul bloc. Confirmer qu'on l'accepte, sachant qu'il est signalé comme tel sur chaque certificat.
5. **Clé de signature Ed25519.** Options : (a) dans `credentials.yml.enc` (la clé privée vit avec `RAILS_MASTER_KEY`, même secret que le reste); (b) fichier séparé monté par Kamal avec sa propre phrase; (c) KMS externe. **Recommandation : (b) minimum**, car (a) place la clé de signature et la base dans le même périmètre de compromission, ce que le certificat doit justement pouvoir dire.
6. **Prestataire d'envoi d'e-mails** (SMTP ou API) et domaine expéditeur. Prérequis de B01a (résumé quotidien), B02a et B02c. Rien n'est configuré aujourd'hui.
7. **Domaine du portail** (par exemple `portail.<votre domaine>`), et si les domaines personnalisés par cabinet sont voulus tout de suite ou plus tard (certificat par domaine).
8. **Protocole d'envoi par morceaux** : tus (gem `tus-server` ou le serveur intégré d'un tiers) ou un protocole minimal maison (sessions + morceaux numérotés + SHA-256). La spec demande d'évaluer tus d'abord; je le ferai en début de B02b, sauf contrainte de votre part.
9. **Langues.** La règle projet est « interface en anglais seulement » (mémoire), la spec demande fr/nl/en. Pour le portail client la question se repose réellement (clients francophones et néerlandophones). Faut-il ajouter `nl` au portail seulement, ou partout?
10. **Données de référence versionnées** : table dédiée `master_data_versions` (spec) ou PaperTrail existant. **Recommandation : la table dédiée, alimentée par trigger SQL**, pour la même raison que pour `posted_at` (non contournable).
11. **Lots existants.** Existe-t-il des lots `executed` réels en production ? Si oui, confirmez qu'on les garde en lecture seule (statut `legacy`) plutôt que de les migrer.
12. **Drapeaux de société** : le dépôt utilise `Entity::FEATURES` (`f01`… `agent`) avec `Entity#feature?`. La spec veut `feature_b01a`…`feature_b02c`. Je propose d'ajouter les neuf clés à `FEATURES` sous la forme `b01a`… (même mécanisme, mêmes écrans de réglages), sauf objection.

## 7. Points ambigus, contradictoires ou incompatibles avec le code

1. **Invariants I12 à I15 déjà pris** : `spec/invariants/i12_foreign_currency_spec.rb` et `i13_imports_and_api_sequences_spec.rb` existent. Proposition : renuméroter les invariants de la signature en **I14 (temps), I15 (lots de paiement), I16 (un seul lot actif), I17 (ancrage)** et mettre à jour la spec. À valider.
2. **Contrôles C18/C19** : `C18` est déjà « document_integrity ». Proposition : **C20** (reconstruction historique divergente) et **C21** (ancrage compromis); C08, C10 et C15 restent libres mais je n'y touche pas.
3. **Étape 17 de F10** : confirmée (`lock_and_bundle`), pas d'écart.
4. **`cancel_requested`** (B01b, cas limites) n'est pas dans la liste des statuts de `payment_batches`. À ajouter à la liste.
5. **`partially_rejected`** : le lot reste `partially_rejected` ou passe `debited` après le traitement des rejets ? B01c dit « `debited` » pour la confirmation et ne décrit pas la sortie de `partially_rejected`.
6. **B01a « premier paiement »** : condition de politique non définie quand le fournisseur a été payé **hors** LedgerFlow (avant l'activation). Comportement prudent proposé : ne compter que les paiements connus du logiciel, donc un fournisseur ancien déclenche « premier paiement » une fois.
7. **Séparation des tâches vs petits cabinets.** `distinct_payment_authorizer` et « l'auteur ne peut pas approuver » rendent un **dossier à une seule personne** inutilisable pour payer. Il faut un réglage explicite de propriétaire (la spec le prévoit en principe 2) et son interface. À décrire dans `B01a.md`.
8. **Facture « sans IBAN de facture »** : le critère « IBAN de la facture ≠ IBAN du fichier tiers » suppose que l'IBAN de la facture est stocké. Aucune colonne ne le porte aujourd'hui. À ajouter à `accounting_invoices` (ou sur le document), alimenté par Peppol et par la saisie.
9. **« Montant du paiement > 2 × moyenne »** (B01a et B01b) : la moyenne se calcule sur quelles factures (5 dernières, 12 mois, toutes) ? La spec dit deux choses. Proposition : les cinq dernières factures validées du tiers, au moins trois pour déclencher.
10. **Rétention des événements `portal_events` « recopiés dans R18 »** : R18 est une chaîne par société et le portail aura aussi des acteurs sans `User`. `AuditLog` a `user_id`/`user_email` seulement; il faut `actor_type` + `actor_id` (migration non destructive, valeur par défaut `user`).
11. **R21 « Ce qui a changé »** : la numérotation R21 est libre (R20 = liasse). OK.
12. **`time_travel.view` pour l'auditeur externe** : déjà inclus dans la spec; il hérite du filigrane F01 (`export_watermark`). À reprendre pour les exports historiques.
13. **Performance de `known_at`** : « moins de 20 % au-dessus » suppose l'index `(entity_id, posted_seq)` et que les requêtes passent par une vue ou un CTE commun. Les requêtes actuelles ne partagent pas une base commune (`open_line_sql.rb` pour R04, SQL propres pour les autres) : risque de dérive entre vue courante et vue historique. Proposition : d'abord une **couche commune** `PostedLines.as_known_at(t)` utilisée par les requêtes migrées une à une, chacune testée par `known_at = maintenant ⇒ rapport courant` (critère 1 de B03a).
13. **Mutation testing** (« Mutant ≥ 85 % ») : `mutant` n'est pas dans le `Gemfile`. Licence commerciale pour un usage non open source. À trancher (point 15 ci-dessous) ou à remplacer par un autre outil.
14. **Contrôle de la couverture** : CLAUDE.md demande SimpleCov ≥ 95 % sur la suite entière; la spec dit « sur son dossier ». Les deux sont compatibles; je mesure sur les deux.
15. **Outils de qualité listés par la spec mais absents** : `mutant`, `i18n-tasks`, détection de secrets (`gitleaks` ou équivalent), accessibilité automatisée (axe). `bullet`, `brakeman` et `bundler-audit` sont présents. Faut-il les ajouter (et lesquels), ou les remplacer par ce qui existe ?

## 8. Plan détaillé de la vague P0 (B01a → B01b → B01c)

Ordre des commits dans chaque capacité : jeux de référence → specs rouges → migrations → modèles/services → policies/contrôleurs/API → écrans → audit/drapeau → i18n/accessibilité → doc. Un commit par ligne ci-dessous. **Aucun commit n'est fait sans votre demande**, comme d'habitude.

### Étape 0 · Préalables communs (avant B01a)

1. `docs/dev/signature/QUESTIONS.md` créé; décisions 1 à 12 consignées.
2. Renuméroter I/C (point 7.1, 7.2) dans la spec.
3. **Second facteur récent** : horodatage `session[:second_factor_at]`, `require_recent_second_factor!(within:)` dans `ApplicationController`, spec (TOTP et passkey). Prérequis de l'export (B01b) et du seuil d'approbation (B01a).
4. `AuditLog` : colonne `actor_type` (défaut `user`), migration réversible, spec que la chaîne v1 ne change pas.
5. Drapeaux `b01a`, `b01b`, `b01c` dans `Entity::FEATURES`; permissions de §2.2 dans `Permissions::MATRIX` (spec de matrice, interface **et** API).
6. Jeu de référence B01 (§13) : fournisseurs, IBAN modifiés/erronés, notes de crédit, paiements partiels, litiges; valeurs attendues calculées **indépendamment** dans `spec/fixtures/reference_ledger/expected/` (dossier à créer : il n'existe pas aujourd'hui).

### B01a · Circuit d'approbation (effort L)

1. Migrations : `approval_policies`, `approval_steps`, `approval_requests` (empreinte de contenu), `approval_decisions`, `approval_delegations`; `accounting_invoices.payment_status` (+ `iban_on_invoice`, point 7.8). Réversibles; aucune donnée existante modifiée (statut initial `not_required` pour l'existant).
2. `Approvals::ContentFingerprint` (champs significatifs de §4.5) : specs d'abord (montant, lignes, échéance, pièce; le libellé ne compte pas).
3. `Approvals::PolicyMatcher` : tableau de cas (montant, fournisseur, projet, devise en EUR à la date de facture, « premier paiement »).
4. `Approvals::Submit`, `Decide` (approuver, refuser avec motif, demander une modification → tâche F08, transférer), `Invalidate` (callback sur les changements significatifs).
5. Séparation des tâches et délégations (non transitives, expiration, pas d'auto-approbation).
6. Escalade et rappels (job Solid Queue, `travel_to`), reroutage d'un approbateur désactivé.
7. Policies et contrôleur « À approuver », approbation groupée, frise sur la fiche facture; API `/api/v1/approvals`.
8. Mobile : écran adaptatif, lien d'e-mail **vers l'écran authentifié uniquement**, seuil `step_up_threshold` (second facteur récent).
9. R14 : séparer approuvé / en attente. Résumé quotidien (compteurs et liens) — dépend de la décision 6.
10. Audit R18, invariants, séquence aléatoire, `B01a.md`, test d'isolation entre sociétés.

### B01b · Lots SEPA et coordonnées bancaires (effort XL)

1. **Décision 1 et 2 obtenues** (fichiers CODA, banques, version du format). Sinon `QUESTIONS.md` et comportement prudent (`pain.001.001.03`).
2. Migrations : `partner_bank_accounts` (IBAN chiffré, statuts, vérification), reprise **non destructive** de `partners.iban` (création d'un compte `unverified` par tiers ayant un IBAN : **à valider avec vous**, sinon tous les lots seraient bloqués), `bank_profiles`, `payment_holds`, nouvelles colonnes de `payment_batches` (statuts, empreinte, document F03), `payment_items`, `payment_item_invoices`; lots existants marqués `legacy`.
3. Flux de vérification d'IBAN : deux personnes, période d'observation, alertes propriétaires, tâche F08 en cas de divergence Peppol; aucune mise à jour automatique.
4. `Payments::Eligibility` (tableau de cas, raisons exactes); verrou + contrainte d'unicité pour I16 (partial unique index sur le lot actif); test de concurrence.
5. Composition (notes de crédit nettes, regroupement, paiement partiel, limites) et `Payments::PreflightReport` (un service par contrôle, rejoué à l'export).
6. `Payments::Sepa::Pain001Builder` déterministe, validation XSD, test de propriété sur le contrôle de somme et les arrondis; document F03 immuable avec SHA-256.
7. Approbation du lot (moteur B01a, `distinct_payment_authorizer`, `authorizer_not_bap_giver`); export avec second facteur récent; lot immuable après export; annulation (y compris `cancel_requested`).
8. Écrans « Paiements » en cinq temps et « Coordonnées bancaires »; permissions `payments.*` et `bank_accounts.verify` (retrait progressif de `payments.manage`).
9. Test « aucune colonne d'identifiant bancaire de l'utilisateur dans le schéma » et masquage des IBAN dans les journaux; chiffrement au repos.
10. Retirer `CreateSettlementJournalEntry` et `MarkInvoicesPaid` du flux (déplacés vers B01c), réécrire `Bank::Simulator::PayBatch`.

### B01c · Confirmation, rapprochement, retours (effort L)

1. Règle 0 dans `MatchBankTransaction` (cas A, A', B, C) avec recherche bornée à cinq paiements; mesure sur les fichiers de la décision 1.
2. `Payments::ConfirmDebit` idempotent (clé unique `payment_items.journal_entry_id`), brouillons de paiement `created_via: payment_batch`, rapprochement n:1 (F02).
3. Validation par lot (`entries.post` + quatre yeux), puis **lettrage exact automatique** (exception explicite à tester : `AutoLetterExact` existe; vérifier son comportement partiel).
4. Rejets, retours (extourne préremplie F07), IBAN repassé en `unverified`, double paiement (`disputed`, tâche, aucun lettrage).
5. Confirmation manuelle avec motif + contrôle R19 tant que le relevé n'est pas rapproché (nouveau contrôle).
6. Alertes (`travel_to`), frise du paiement, indicateurs, export « Paiements exécutés ».
7. Invariant I15 (débit = paiements confirmés) en séquence aléatoire; parcours système complet (facture, BAP, lot, export, débit, confirmation, lettrage); `B01c.md`.

### Risques principaux de P0

- **Élevé** : remplacer le flux Payments existant sans casser les lots déjà exécutés; reprise des IBAN actuels (bloquer tout paiement ou créer des comptes `unverified` en masse).
- **Élevé** : validation de la règle 0 sans CODA réel de banque; risque de faux positif à confiance 100 (cible : zéro).
- **Moyen** : second facteur « récent » touche toute la chaîne de connexion (TOTP, passkey, codes de secours).
- **Moyen** : configuration SMTP absente (résumé d'approbations, alertes propriétaires).
- **Moyen** : `Accounting::FiscalYear.current` (bug connu) et fuite de `I18n.locale` en spec, que le module Payments rencontre directement.

## 9. Ce que j'attends de vous

Dites-moi : (1) si la renumérotation I14 à I17 / C20 à C21 vous convient, (2) vos réponses aux décisions 1, 2, 9, 11 et 12 (celles qui bloquent le début de B01), (3) si je démarre l'étape 0 puis B01a. Je ne commence rien avant votre validation.

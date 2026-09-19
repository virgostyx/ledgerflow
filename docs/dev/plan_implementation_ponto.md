# Plan d'implémentation : intégration bancaire Ponto dans l'application comptable

Document destiné à l'agent de développement. Il décrit *quoi* construire, *dans quel ordre*,
avec quels critères d'acceptation. L'agent doit d'abord lire le dépôt (section 1) et
adapter les noms de modèles, dossiers et conventions à ce qu'il y trouve.

---

## 0. Objectif et périmètre

**Objectif** : connecter l'application comptable à Ponto (Isabel Group, PSD2 AIS + PIS) pour :

1. importer automatiquement les comptes et transactions bancaires ;
2. les rapprocher des factures (clients et fournisseurs) et proposer/générer les écritures ;
3. initier des paiements fournisseurs, avec confirmation explicite de l'utilisateur ;
4. tester tout cela dans le **sandbox gratuit** de Ponto avant toute utilisation réelle.

**Hors périmètre (v1)** : agrégation multi-fournisseurs (Enable Banking, etc.), paiements
récurrents/permanents, multi-devises complexe, OAuth « Ponto Connect » multi-clients
(la v1 utilise une *intégration personnalisée* : grant `client_credentials`).

**Déjà fourni** (dossier `ponto_client/`) : `Ponto::Client` (Faraday, JSON:API, découverte des
URI), tâche `ponto:smoke`, 4 tests Minitest/WebMock qui passent. Ce code est un **point de
départ à durcir**, pas un livrable final. Plusieurs endpoints y sont marqués « à vérifier »
(voir section 4, Phase 1).

---

## 1. Règles de travail pour l'agent

- **Commencer par lire** : `db/schema.rb`, `Gemfile`, `config/`, `app/` (structure des dossiers),
  `spec/` (conventions de tests), le plan comptable et les modèles de factures/écritures.
  Ne pas supposer les noms : les relever et les réutiliser.
- **TDD** : écrire le test (RSpec) avant le code. Convertir les tests Minitest fournis en RSpec
  si le dépôt utilise RSpec.
- **Réutiliser les conventions existantes** : organisateurs/actions **LightService** pour la logique
  métier, **ViewComponent** + Stimulus + Tailwind pour l'UI, le backend de jobs déjà en place
  (ne pas en introduire un nouveau), le gem d'argent/décimaux déjà utilisé s'il existe.
- **Petites PR** : une phase = une ou plusieurs PR relues séparément (section 6).
- **Ne jamais appeler l'API réelle (production)** depuis les tests, le développement ou la CI.
  Le sandbox n'est utilisé que dans des tests explicitement marqués `:sandbox`, exclus par défaut.
- **Ne jamais inventer un endpoint ou un attribut** : vérifier dans les sources listées en Phase 1.
  En cas de doute, s'arrêter et poser la question.
- **Aucun secret dans le dépôt** (ni dans les cassettes VCR, ni dans les logs, ni dans les fixtures).
- **Argent** : jamais de `Float` dans le domaine. Décimaux (`BigDecimal`) ou centimes entiers.
- Toute action qui déplace de l'argent (paiement) exige une **confirmation utilisateur explicite**
  et une trace d'audit. Aucun paiement automatique en v1.

---

## 2. Architecture cible

```
UI (ViewComponent)            Jobs                    Services (LightService)         Client HTTP
─────────────────────         ──────────────────      ─────────────────────────       ───────────
BankConnection settings  ──►  Bank::SyncAllJob   ──►  Bank::SyncAccounts        ──►  Ponto::Client
Comptes & transactions   ──►  Bank::ImportJob    ──►  Bank::ImportTransactions       (Faraday, JSON:API,
Rapprochement (review)   ──►  Bank::MatchJob     ──►  Bank::MatchTransactions         token 30 min)
Paiements (confirmation) ──►  Bank::PaymentStatusJob  Bank::CreatePayment
                                                       Bank::BookTransaction
```

- `Ponto::Client` ne connaît **que** HTTP/JSON:API. Aucune logique comptable dedans.
- Les organisateurs LightService orchestrent : appel client → mapping → persistance → événements.
- Les données brutes reçues sont conservées (`raw_payload` jsonb) pour audit et re-traitement.

---

## 3. Modèle de données (à adapter au schéma existant)

Nommer selon les conventions du dépôt. Si l'application est multi-société/multi-tenant, **toutes**
les tables ci-dessous portent la clé de tenant et sont scopées ; sinon, l'omettre.

### `bank_connections`
| Colonne | Type | Notes |
|---|---|---|
| `environment` | string/enum | `sandbox` ou `live` ; défaut `sandbox` |
| `client_id` | string | chiffré (`encrypts`) |
| `client_secret` | string | chiffré (`encrypts`) ; affiché **une seule fois** côté Ponto, jamais réaffiché dans l'UI |
| `status` | enum | `pending`, `active`, `error`, `revoked` |
| `last_error` | text | message sans secret |
| `last_synced_at` | datetime | |

Activer Active Record Encryption (clés dans `credentials`) si ce n'est pas déjà fait.
Si l'application est mono-société, une seule connexion suffit, mais garder la table (plus propre
que des variables d'environnement pour le secret, et permet de changer sans déploiement).

### `bank_accounts`
`bank_connection_id`, `ponto_account_id` (unique), `iban`, `currency`, `holder_name`,
`current_balance`, `available_balance`, `balance_synced_at`, `ledger_account_id`
(→ compte comptable de classe 55, ex. 550xxx ; **à confirmer avec le plan comptable de l'app**),
`journal_id` (journal financier), `active` (boolean).

### `bank_transactions`
| Colonne | Notes |
|---|---|
| `bank_account_id` | |
| `ponto_transaction_id` | **unique** avec `bank_account_id` → import idempotent |
| `amount` | décimal signé (crédit +, débit −) ; `currency` |
| `value_date`, `execution_date` | |
| `counterpart_name`, `counterpart_reference` (IBAN) | |
| `remittance_information`, `remittance_information_type` | |
| `structured_communication` | communication structurée normalisée (12 chiffres), extraite si valide |
| `status` | `imported`, `suggested`, `matched`, `booked`, `ignored` |
| `matched_document_type/id` | polymorphe vers facture client/fournisseur |
| `journal_entry_id` | écriture générée |
| `raw_payload` | jsonb |

Index : unique `(bank_account_id, ponto_transaction_id)`, index sur `structured_communication`,
`status`, `execution_date`.

### `bank_payments`
`bank_account_id`, `supplier_invoice_id` (nullable), `amount`, `currency`, `creditor_name`,
`creditor_iban`, `remittance_information`, `requested_execution_date`,
`idempotency_key` (uuid, **généré et persisté avant l'appel API**), `ponto_payment_id`,
`status` (`draft`, `submitted`, `awaiting_signature`, `signed`, `executed`, `failed`, `cancelled`),
`failure_reason`, `created_by_id`, `confirmed_by_id`, `confirmed_at`, `signature_url` (si redirection),
`raw_payload`.

### `bank_events` (audit, optionnel mais recommandé)
Journal append-only : qui a fait quoi, quand (connexion créée, paiement confirmé, échec, etc.).

---

## 4. Phases d'implémentation

### Phase 0 : Préparation
- Créer la branche, ajouter `faraday` (et `webmock` + `vcr` en test si absents).
- Copier `Ponto::Client` dans `app/services/ponto/` (ou l'emplacement conventionnel du dépôt).
- Convertir `client_test.rb` en `spec/services/ponto/client_spec.rb` (RSpec).
- Ajouter `config.filter_parameters += [:client_secret, :access_token, :authorization]`.
- Ajouter les variables/credentials : voir annexe A.

**Critère d'acceptation** : la suite de tests existante passe ; les 4 tests du client sont verts en RSpec.

### Phase 1 : Durcir et vérifier `Ponto::Client`
Vérifier chaque endpoint « à vérifier » **avant** d'aller plus loin. Sources, dans cet ordre :
1. la référence API Ponto (`documentation.myponto.com/api`, page en JavaScript : utiliser un navigateur) ;
2. le code source du gem Ruby officiel `ibanity` (dépôt GitHub `ibanity/ibanity-ruby`, dossier
   `lib/ibanity/api/ponto_connect/`) : contient chemins et types de ressources ;
3. le crate `pontoconnect_rs` (docs.rs), généré depuis la spécification OpenAPI : liste les
   attributs exacts de chaque requête.

Points à vérifier, un par un, avec test à l'appui :
- [ ] chemin du token et méthode d'authentification (Basic vs corps) ;
- [ ] `GET /financial-institutions` ;
- [ ] `GET /accounts/{id}/transactions` : paramètres de pagination (`page[limit]`, `page[after]`…) ;
- [ ] `POST /synchronizations` : attributs (`resourceType`, `resourceId`, `subtype`, `customerIpAddress`) ;
- [ ] `POST /accounts/{id}/payments` : attributs exacts, format du montant, en-tête d'idempotence ;
- [ ] `GET` d'un paiement (pour suivre son statut) ;
- [ ] création de transactions sandbox et liste des comptes sandbox : attributs exacts ;
- [ ] format des webhooks et vérification de signature (voir Phase 5).

Durcissements à implémenter :
- **Décimaux** : parser avec `JSON.parse(body, decimal_class: BigDecimal)` ; sérialiser les montants
  en nombre JSON correct (arrondi à 2 décimales, pas de notation scientifique). Test : `0.1 + 0.2`, `1250.10`, `99.5`.
- **Erreurs typées** : `Ponto::AuthError` (401/403), `Ponto::NotFound` (404), `Ponto::RateLimited` (429),
  `Ponto::ServerError` (5xx), `Ponto::ValidationError` (422), toutes sous `Ponto::Error`.
- **Retries** : uniquement sur GET et sur erreurs réseau/429/5xx, avec backoff exponentiel et jitter, max 3.
  **Jamais** de retry automatique d'un POST sans clé d'idempotence.
- **Token** : cache partagé (`Rails.cache`) avec expiration ~25 min, protégé contre les accès concurrents ;
  invalidation et un seul renouvellement sur 401.
- **Logs** : niveau debug seulement, sans en-têtes `Authorization` ni corps sensibles.
- Timeouts configurables ; `User-Agent` explicite.

**Critère d'acceptation** : tous les endpoints ci-dessus sont couverts par un test (WebMock ou VCR
avec cassettes nettoyées) ; un test `:sandbox` (désactivé par défaut) passe avec de vraies clés sandbox ;
la checklist est cochée dans la PR avec la source de chaque vérification.

### Phase 2 : Modèles et migrations
- Créer les tables de la section 3 avec contraintes (NOT NULL, FK, index uniques).
- Modèles avec validations, enums, `encrypts`, scopes (`credits`, `debits`, `unmatched`).
- Factories RSpec ; specs de modèle (validation, unicité, chiffrement effectif : la valeur en base n'est pas lisible).

**Critère d'acceptation** : migrations réversibles ; specs verts ; aucun secret en clair en base.

### Phase 3 : Configuration de la connexion (UI)
- Écran « Connexion bancaire » (ViewComponent) : environnement (sandbox par défaut), client id,
  client secret, bouton « Tester la connexion » (appelle `accounts`), statut et dernière synchro.
- Le secret n'est **jamais** réaffiché ; pour le changer, on le remplace.
- Autorisation : réservée aux rôles administrateur/comptable existants.
- Bandeau bien visible quand l'environnement est `live`.

**Critère d'acceptation** : specs de composant et de système ; un mauvais secret affiche un message
clair sans fuite ; un test vérifie que le secret n'apparaît pas dans le HTML rendu.

### Phase 4 : Synchronisation des comptes
- `Bank::SyncAccounts` (LightService) : appelle `accounts`, crée/met à jour `bank_accounts`
  par `ponto_account_id`, met à jour soldes et `balance_synced_at`.
- Écran de liaison : associer chaque compte bancaire à un compte du plan comptable (classe 55) et
  à un journal financier. Un compte non lié ne peut pas générer d'écritures.

**Critère d'acceptation** : idempotent (deux exécutions = mêmes enregistrements) ; specs avec réponses simulées.

### Phase 5 : Import des transactions
- `Bank::ImportTransactions` : pagination complète, dédoublonnage via l'index unique, conversion des
  montants en décimaux, extraction de la communication structurée (annexe C), stockage du `raw_payload`.
- Import initial (historique disponible) puis import incrémental depuis la dernière date connue,
  avec **chevauchement de sécurité** de quelques jours (le dédoublonnage rend cela sans risque).
- Déclenchement : job périodique (`Bank::SyncAllJob`), plus un bouton « Actualiser ».
- **Attention à la synchronisation manuelle** : en production, Ponto exige qu'une synchronisation
  manuelle soit déclenchée en présence de l'utilisateur, avec son **adresse IP réelle** ; utiliser une
  fausse IP ou l'appeler sans lui viole les conditions d'utilisation et peut entraîner le blocage
  de l'intégration. Donc :
  - le job périodique **lit seulement** les données de la dernière synchronisation de Ponto ;
  - le bouton « Actualiser » (action utilisateur) peut appeler `synchronize` avec `request.remote_ip` ;
  - en sandbox, la limite entre deux synchronisations est d'environ 10 secondes (5 minutes pour la plupart des banques réelles).
- Option (phase ultérieure) : webhook de nouvelles transactions ; ne l'activer qu'après avoir vérifié
  le format et la validation de signature ; l'endpoint doit répondre vite et déléguer à un job.

**Critère d'acceptation** : réimporter deux fois ne crée aucun doublon ; un import interrompu à
mi-parcours se termine correctement au passage suivant ; specs couvrant pagination et erreurs API.

### Phase 6 : Rapprochement bancaire
`Bank::MatchTransactions` produit une **suggestion**, jamais une écriture silencieuse au début.

Règles, par ordre de confiance décroissante :
1. **Communication structurée valide** identique à celle d'une facture ouverte (client ou fournisseur) → confiance élevée.
2. **IBAN de la contrepartie** connu + montant exact d'une facture ouverte → confiance élevée.
3. Montant exact + nom de contrepartie proche + date plausible → confiance moyenne.
4. Références de facture dans la communication libre (numéro de facture) → confiance moyenne.
5. Sinon : non rapproché → file de traitement manuel.

Cas à gérer explicitement : paiement partiel, paiement groupé de plusieurs factures, trop-perçu,
doublon de paiement, note de crédit, frais bancaires, virement entre comptes propres, devise différente.

Comptabilisation (`Bank::BookTransaction`), **à confirmer avec le plan comptable de l'application** :
- encaissement client : débit 550 (banque) / crédit 400 (clients) ;
- paiement fournisseur : débit 440 (fournisseurs) / crédit 550 (banque) ;
- non identifié : compte d'attente (499) en attendant traitement ;
- virement interne : compte 580 ;
- frais bancaires : compte de charges financières approprié.
Les écritures respectent les règles existantes de l'application (période ouverte, équilibre, numérotation, TVA le cas échéant).

UI de revue (ViewComponent) : liste des transactions avec suggestion, niveau de confiance,
actions « Valider », « Modifier », « Ignorer ». Validation en lot possible pour la confiance élevée.

**Critère d'acceptation** : jeu de scénarios de test couvrant chaque règle et chaque cas limite ;
aucune écriture déséquilibrée possible ; la validation est idempotente (double clic = une seule écriture).

### Phase 7 : Initiation de paiements
Flux : facture fournisseur → « Préparer un paiement » → écran de confirmation → appel API → suivi.

- Validations avant tout appel : IBAN valide (clé de contrôle), montant > 0, devise = devise du compte,
  facture non déjà payée, communication conforme (jeu de caractères limité côté banque : le nom du
  bénéficiaire est limité à 60 caractères), banque compatible (`paymentsEnabled` / `bulkPaymentsEnabled`).
- **Idempotence** : générer et **enregistrer** `idempotency_key` **avant** l'appel ; en cas d'erreur réseau,
  rejouer avec la **même** clé, jamais une nouvelle.
- Confirmation explicite par un utilisateur autorisé ; enregistrer `confirmed_by`, `confirmed_at` ;
  séparation des rôles si l'application le permet (préparateur ≠ valideur).
- Après création, le paiement doit être **signé** auprès de la banque : soit dans le tableau de bord Ponto,
  soit via l'URL d'autorisation renvoyée si `redirectUri` est fourni. Statut `awaiting_signature` jusqu'à confirmation.
- `Bank::PaymentStatusJob` : suit l'état du paiement jusqu'à un état final ; à l'exécution, rapproche
  automatiquement la transaction bancaire résultante avec le paiement et la facture.
- Limite du sandbox : l'exécution différée d'un paiement ne peut pas être simulée.

**Critère d'acceptation** : impossible de créer deux paiements pour la même intention (test de rejeu) ;
aucun paiement sans confirmation ; chaque paiement a une trace d'audit ; tests des états d'échec.

### Phase 8 (optionnelle) : Import de fichiers CODA / CAMT.053
Utile en secours, pour les banques non couvertes et pour des tests déterministes.
- Parseur CODA (standard belge Febelfin) et CAMT.053 produisant les mêmes `bank_transactions`.
- Fixtures de fichiers de test dans `spec/fixtures/bank/`.

### Phase 9 : Observabilité, sécurité, conformité
- Alertes sur échecs répétés (connexion en erreur, secret invalide, quota, synchronisation trop ancienne).
- Contrôle d'accès par rôle sur toutes les pages et actions bancaires ; journal d'audit consultable.
- Rotation des secrets documentée (régénérer dans Ponto, remplacer dans l'UI).
- RGPD : les données bancaires sont des données personnelles ; définir la durée de conservation,
  ne pas les copier dans les logs, chiffrer les sauvegardes.
- Documentation développeur (`docs/bank_integration.md`) : architecture, exécution locale, dépannage.

### Phase 10 : Passage en production
Liste de contrôle :
- [ ] Organisation Ponto live créée et vérifiée par Isabel (requis pour signer des paiements hors sandbox).
- [ ] Intégration personnalisée live créée avec le périmètre minimal nécessaire (AIS seul si pas de paiements).
- [ ] Nouvelles clés saisies via l'UI (`environment = live`) ; aucune clé sandbox réutilisée.
- [ ] Première synchronisation observée en lecture seule ; import vérifié sur une période courte.
- [ ] Rapprochement en mode « suggestion » uniquement pendant la première période.
- [ ] Premier paiement réel de faible montant, confirmé et signé manuellement.
- [ ] Alertes et sauvegardes vérifiées.

---

## 5. Stratégie de tests

- **Unitaires** (RSpec) : client, mapping, extraction/validation de communication structurée, règles de rapprochement.
- **Services** : organisateurs LightService avec le client doublé (WebMock/VCR).
- **Composants/système** : formulaires, écran de revue, confirmation de paiement.
- **Sandbox** (`--tag sandbox`, exclu par défaut et de la CI) : un test de bout en bout réel :
  créer un dépôt fictif → synchroniser → importer → rapprocher.
- **Scénarios sandbox à créer** : encaissement exact avec communication structurée ; paiement partiel ;
  deux virements pour une facture ; virement sans communication ; doublon ; débit (frais) ; paiement fournisseur.
- Cassettes VCR : filtrer `Authorization`, `client_secret`, IBAN réels ; relire avant de commiter.
- Couverture minimale attendue sur le code neuf : viser 90 %+ et 100 % sur la validation d'IBAN,
  la communication structurée et la comptabilisation.

---

## 6. Découpage en PR (ordre recommandé)

| PR | Contenu | Dépend de |
|---|---|---|
| 1 | Phase 0 : import du client, RSpec, filtres de logs | |
| 2 | Phase 1 : vérification des endpoints + durcissement du client | 1 |
| 3 | Phase 2 : migrations et modèles | |
| 4 | Phase 3 : écran de connexion | 2, 3 |
| 5 | Phase 4 : synchronisation des comptes + liaison au plan comptable | 4 |
| 6 | Phase 5 : import des transactions | 5 |
| 7 | Phase 6a : extraction et règles de rapprochement (sans écriture) | 6 |
| 8 | Phase 6b : comptabilisation + écran de revue | 7 |
| 9 | Phase 7 : paiements | 8 |
| 10 | Phase 9 : alertes, audit, documentation | 9 |
| 11 | Phase 8 (optionnel) : CODA/CAMT | 6 |

**Définition de « terminé » pour chaque PR** : tests verts, linter (RuboCop) propre, aucune
régression, migration réversible, pas de secret, description listant ce qui a été vérifié dans
la référence API.

---

## 7. Questions à trancher (l'agent doit les poser plutôt que deviner)

1. L'application est-elle multi-société ? (détermine le scoping et où stocker les secrets)
2. Où sont les factures fournisseurs et clients (y compris celles reçues via Peppol) ? Quels statuts « ouvert/payé » existent ?
3. Quel backend de jobs est en place, et existe-t-il déjà un mécanisme de planification périodique ?
4. Quel plan comptable exact est utilisé (numéros de comptes 400, 440, 499, 550, 580…) ?
5. Quelles règles de période ouverte/clôture s'appliquent aux écritures générées ?
6. Les paiements doivent-ils être groupés (`bulk-payments`) dès la v1 ?
7. Quels rôles peuvent préparer et valider un paiement ?

---

## Annexes

### A. Configuration
```
PONTO_CLIENT_ID=...              # sandbox pour dev/test ; live uniquement en production
PONTO_CLIENT_SECRET=...
PONTO_BASE_URL=https://api.ibanity.com/ponto-connect   # défaut
PONTO_TOKEN_URL=                                       # optionnel (sinon découvert)
```
Avec la table `bank_connections`, ces variables ne servent que pour la tâche `ponto:smoke` et les tests sandbox.

### B. Ordre de grandeur des contraintes de l'API (documentées)
- Jeton d'accès : 30 minutes.
- Synchronisation manuelle : intervalle minimal ~5 min (banques réelles), ~10 s (sandbox) ; en production, en présence de l'utilisateur uniquement.
- Sandbox : comptes et transactions fictifs préexistants ; création et modification de transactions possibles, **suppression impossible**.
- Signature d'un paiement : dans le tableau de bord Ponto ou via le portail d'autorisation ; en sandbox, pas de vérification préalable de l'organisation.

### C. Communication structurée belge (`+++123/4567/89012+++`)
Douze chiffres : les dix premiers sont la base, les deux derniers sont le contrôle.
Contrôle = (base mod 97), et 97 si le reste est 0.
```ruby
module StructuredCommunication
  PATTERN = %r{\+{3}(\d{3})/(\d{4})/(\d{5})\+{3}|\b(\d{12})\b}

  def self.extract(text)
    return unless (m = PATTERN.match(text.to_s))
    digits = m[4] || (m[1] + m[2] + m[3])
    valid?(digits) ? digits : nil
  end

  def self.valid?(digits)
    return false unless digits.match?(/\A\d{12}\z/)
    base = digits[0, 10].to_i
    check = digits[10, 2].to_i
    expected = base % 97
    expected = 97 if expected.zero?
    check == expected
  end
end
```
À tester avec des cas valides, invalides, avec/sans séparateurs et un reste de 0.

### D. Sources de vérité
- Documentation Ponto : `documentation.myponto.com` (intégrations personnalisées, sandbox, paiements).
- Documentation Ibanity : `documentation.ibanity.com/ponto-connect`.
- Gem Ruby `ibanity` et crate `pontoconnect_rs` (spécification OpenAPI générée).

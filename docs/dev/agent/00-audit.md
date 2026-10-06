# Audit LedgerFlow pour l'agent IA (2026-10-06)

Rails 8.1.4 / Ruby 3.3.5. Aucune trace de code agent (`app/agent/` absent).

## 1. État réel des dépendances
| Dépendance | État |
|---|---|
| Rapports | Services/queries sous `app/services/accounting`, `app/queries/accounting` (détail §2). Pas de `Ledger::*`: l'équivalent est `Accounting::*` (`PostJournalEntry`, etc.) |
| Écriture | `Accounting::PostJournalEntry` (LightService: période ouverte, quatre yeux, équilibre, numérotation, verrou, audit). Brouillon = `status: draft` |
| Permissions F01 | `Permissions::MATRIX` (`app/policies/permissions.rb`), rôles admin/accountant/manager/auditor/assistant + `CustomRole`, `ApplicationPolicy#can?`, restriction par journal (`journal_ids`), **pas** par compte. Tenant: `acts_as_tenant :entity`; `Current` ne porte pas l'entité |
| Audit R18 | `Accounting::AuditLog`, append-only (trigger), chaîne SHA-256, `AuditTrailed` sur 22 modèles, `Current.api_client`. Pas de purge |
| Drapeaux | `Entity#features` jsonb + `Entity::FEATURES` (f01…f13). **Pas** de drapeau de plateforme (interrupteur d'urgence §4 à créer) |
| Documents F03 | Active Storage, `PDF::Reader`, `extracted_data` jsonb, pas d'OCR |
| API F13 | Clés `lf_…` (`ApiClient`, `action_scopes`), JWT hérité fermé, problem+json seulement sur `v1/public`, OpenAPI 3.1 `docs/api/openapi-v1.json` |
| Jobs | Solid Queue, **une seule file `default`**, pas de `queue.yml`, `recurring.yml` prod seulement |
| Flux | Turbo Streams + Solid Cable (CSP `ws/wss` ok). Pas de SSE |
| Chiffrement | Active Record encryption natif (webhooks, user, entity); clés prod dans credentials |
| Gems absents | client LLM, mutant, i18n-tasks, pgvector, rendu Markdown. Présents: bullet, capybara, simplecov (min 95), rack-attack (MemoryStore par processus), noticed, pundit, jwt |
| Secrets | credentials Rails; CSP: `style_src unsafe-inline`, nonce sur script-src |
| F01–F13 | Livrées derrière drapeau: F01, F02, F03, F08, F09, F10, F13. Sans drapeau: F04, F06 (3 réserves), F07, F11. F12a livrée, F12b non appliquée sans validation comptable. F05 absente |

## 2. Outils du §5 → services existants
Tous les services prennent des modèles AR ou des kwargs Ruby (pas d'ids): la couche outil doit résoudre ids → modèles et parser les dates. Aucun n'a de curseur, de limite ni de `ledger_version` réutilisable. Le tenant est implicite: aucun `entity_id` dans les schémas (conforme au §6).

| Outil | Service (app/) | Paramètres réels | Manque |
|---|---|---|---|
| get_trial_balance | `TrialBalanceReport` / `TrialBalanceQuery` | `Reports::Filters`; query: fiscal_year, as_of, date_from, exclude_closing | Filtres `include_drafts`, journaux, tiers, comptes **déclarés mais ignorés**; pas de limite |
| get_ledger | `GeneralLedgerQuery` | account, fiscal_year, dates, partner, journal, lettering | Un compte par appel, pas de grand livre multi-comptes ni « tous comptes d'un tiers » (R03), pas de curseur, tout chargé en Ruby, pas de group_by tiers/mois |
| get_journal_entry | aucun (modèle `JournalEntry`) | — | Fine recherche par id/référence à écrire |
| get_aged_balance | `AgedBalanceQuery` (+ByCurrency) | kind, as_of | Pas de filtre tiers ni de limite; agrégation en Ruby (viole la règle « agrégation SQL » de CLAUDE.md côté rapport, à signaler) |
| list_unreconciled | `UnletteredLinesQuery` | kind, as_of, min_age_days | Pas de filtre tiers ni de curseur |
| get_bank_reconciliation | `BankReconciliationQuery` | bank_account, as_of | Listes `bn`/`sn` non bornées |
| get_financial_statements | `AnnualAccounts`, `CashFlowStatement` | fiscal_year, as_of | Modèle abrégé seul; pas de bilan mensuel |
| get_vat_return | `VatGridQuery`, `IntracomListingQuery` | fiscal_year_id, période | **Ne pas** envelopper `GenerateVatReturn` (écrit une déclaration) |
| get_budget_vs_actual | **aucun** | — | **Bloqué**: pas de budget dans LedgerFlow, BudgetFlow = entrant JWT seulement. Outil à reporter ou à retirer du P0 |
| get_dashboard_kpis | `DashboardKpis` | fiscal_year, as_of, `only:` | 10 KPI; `ledger_version` privée |
| get_consistency_findings | `Consistency::Runner`, `ConsistencyFinding` | check_id, severity, subject, fingerprint | Voir §5 |
| get_audit_trail | `AuditLogsQuery` | hash de params | Pas de pagination |
| search_accounts / partners | `Account.filter_by`, `Partner.filter_by` | `q` | `label_nl` non cherché, pas de limite |
| search_documents | `Document.search` | trigram, 8 mots | Limite seulement |
| list_vat_codes | `VatCode` | — | Non scopé tenant (à vérifier) |

Champs absents: `partners.is_natural_person` (§7: pseudonymisation), `entries.created_via` (§10), `ledger_version` partagée (§8 « Vérifier », cache §16). `partners.language` existe (défaut `fr`).

## 3. Chemins d'écriture que l'agent ne doit jamais atteindre
Écritures **hors service** (le registre d'outils ne doit référencer aucune de ces classes):
- Contrôleurs: `accounting/journal_entries_controller` (new/save/update/destroy), `api/v1/public/entries_controller` (`lines.destroy_all`, `create!`, `SET CONSTRAINTS … DEFERRED`), `partners_controller` (+ API), `settings/accounts_controller`, `fiscal_years_controller`, `invoices`/`recurring_invoices` (`destroy!`), `consolidation_runs` (`entry.destroy`), `documents_controller` (`update_columns`), `imports_controller`, `entities_controller`.
- Modèles/services avec SQL ou écriture de masse: `JournalEntryLine#resync_amount_residual!` (UPDATE brut), `UnletterLines` / `RemoveAllocation` (destroy), `Closing::Steps::CarryForward` (`update_all`), `Consistency::Runner` (`insert_all`).
- Hors application: `lib/tasks/ledger.rake` (INSERT brut sans audit), `db/seeds.rb`, `lib/seeders/*`, `lib/tasks/closing.rake`.
- Services d'écriture légitimes à exclure de la liste blanche de l'agent: tout `Accounting::{Post*,Reverse*,Letter*,Unletter*,Lock*,Unlock*,Close*,Import*,Pay*,Book*,Allocate*}`, `Closing::*`, `Payments::*`, `Imports::*`, `Fx::Revalue`, `Peppol::ReceiveInvoice`, `GenerateVatReturn`.
- Unique point d'écriture autorisé (A07): création d'un brouillon via le **même chemin que le contrôleur d'écriture** (aujourd'hui `JournalEntry.new/save`, pas de service de brouillon dédié). À extraire d'abord en service `Accounting::CreateDraftEntry` (+ `created_via`), sinon A07 duplique la logique du contrôleur.
- Test d'absence de chemin d'écriture (§17): liste blanche de classes appelées + garde dynamique (transaction en lecture seule pendant `Runner`), à écrire en P0.

## 4. Décisions à prendre avec vous
| # | Décision | Options / conséquences |
|---|---|---|
| D1 | Fournisseur et modèles | Gem officiel Anthropic (si le SDK Ruby existe et gère streaming/outils) vs client Faraday maison (Faraday déjà présent). Identifiants dans credentials. À confirmer dans la doc officielle |
| D2 | Langues | Spec: fr/nl/en. Projet: UI **anglaise seule**, locales en/fr, pas de nl, locale forcée. Option recommandée: réponses de l'agent dans la langue de l'utilisateur, UI du panneau en anglais, nl reporté |
| D3 | Cache de prompts | Par défaut off en P0; activation après lecture de la doc et mesure |
| D4 | Embeddings (A06) | Plein texte PostgreSQL d'abord (spec). pgvector absent: décision reportée à P1 |
| D5 | Mode de document (A09) | `text_only` par défaut; `full_document` seulement avec votre accord |
| D6 | Rétention | 90 jours par défaut (spec); pas de purge d'audit existante |
| D7 | Budget / quotas | 20 q/h, 100 q/j, 3 générations simultanées (spec). Montants de budget mensuel à fixer après pilote |
| D8 | Streaming | Turbo Streams + Solid Cable (existant) plutôt que SSE; concurrence Puma à mesurer |
| D9 | Interrupteur d'urgence | Pas de drapeau plateforme: créer (ENV / table de réglages). Choix à faire |
| D10 | Rate limit | `MemoryStore` par processus: insuffisant pour des quotas agent; utiliser Solid Cache ou la table `agent_usage` |
| D11 | Outil `get_budget_vs_actual` | Bloqué (pas de budget): le retirer du P0 ou attendre R11/BudgetFlow |

## 5. Ambiguïtés, contradictions et incompatibilités avec le code
1. **R19**: spec « C01–C17, I1–I11 ». Réalité: 15 contrôles, C01–C07, C09, C11–C14, C16–C18 (C08, C10, C15 absents, C18 existe). `C11` n'émet que I2, I6, I7, I11; I1, I3, I4, I5, I8, I9, I10 sont testés sans être remontés; I12/I13 existent en spec. Les critères A08 (« 17 contrôles + 11 invariants ») sont inapplicables tels quels. Exemples du §11 cités (C04, I5, I7, C09, C10) à revérifier: C10 n'existe pas.
2. **API**: « API REST JWT existante » faux: clés `lf_…` (JWT fermé). La spec A01 (`/api/v1/agent/…`) doit utiliser l'auth ApiClient + `action_scopes`, avec nouvelles scopes.
3. **`Ledger::PostEntry`** n'existe pas: nom réel `Accounting::PostJournalEntry`; pas de mode brouillon dédié (§3 ci-dessus).
4. **Chemins** `docs/agent|features|reports/SPEC.md` → `docs/dev/…/spec.md`.
5. **Permissions**: noms de la spec (`accounts.view`, `partners.view`, `reports.view`, `entries.view`, `documents.view`, `agent.*`) à mapper sur `Permissions::MATRIX` (clés actuelles type `records.write`, `entries.post`, `audit.view`…). Aucune restriction par compte, contrairement à « restrictions par compte de F01 » du §6. Rôles: spec parle de Lecteur/Auditeur externe; code: `manager` (Reader), `auditor`.
6. **`Current`** ne contient pas l'entité: `Agent::Context` doit la prendre depuis `ActsAsTenant`/`UserEntity.current`. Policy d'outil = `UserEntity#allows?`.
7. **Drapeaux**: `Entity::FEATURES` lève `ArgumentError` sur clé inconnue: ajouter `agent` (+ `agent_a05`…) aux constantes et libellés.
8. **Règle de projet vs rapports**: CLAUDE.md impose l'agrégation en SQL, mais `AgedBalanceQuery`, `GeneralLedgerQuery`, `UnletteredLinesQuery` agrègent en Ruby. Pour les outils: parité avec le rapport (spec) mais risque de latence/mémoire sur gros dossiers; à décider (réécrire en SQL ou limiter).
9. **Filtres `Reports::Filters` ignorés** (`include_drafts`, tiers, journaux): le contrat de sortie §5 `filters_applied` exige la vérité; corriger ou ne pas exposer ces filtres.
10. **Mutant, i18n-tasks, pgvector, Markdown**: absents; le §17 exige mutant (≥85 %) et i18n-tasks. Ajouts de gems à valider.
11. **Chiffrement**: seules `encrypts` natives, usage sur 3 modèles; `agent_*` devront déclarer `encrypts` (clés en place).
12. **A12 vs P0**: A12 apparaît en P0 mais avec 30 cas dont l'attendu « calculé indépendamment » repose sur le jeu de référence (`reference_ledger_seeder` existe: à réutiliser).
13. Documents `Document.search` pour `search_documents`: pas d'OCR, donc « scans » d'A09 supposent un moteur d'OCR à choisir (non prévu).
14. File d'attente unique `default`: créer `agent_interactive` / `agent_batch` (§16) et `queue.yml`.
15. Qualité de la spec elle-même: A08 livré avant A07 mais le tableau §3 lui donne l'ordre 8 (cohérent); `QUESTIONS.md` agent à créer.

## 6. Plan détaillé P0 (tâche par tâche, ordre des commits)
Préalables (hors capacité):
- C0.1 Trancher D1, D2, D9, D11 (réponses de l'utilisateur), consigner dans `docs/dev/agent/QUESTIONS.md`.
- C0.2 Ajouter `agent` à `Entity::FEATURES`/labels + spec (rouge→vert).
- C0.3 Mappage des permissions agent dans `Permissions::MATRIX` (`agent.use`, `agent.propose`, `agent.memory.manage`, `knowledge.manage`, `agent.configure`, `agent.conversations.review`) + specs de policy par rôle.
- C0.4 `Accounting::CreateDraftEntry` extrait du contrôleur (+ `created_via`) — peut attendre A07.

A01 Socle conversationnel (§4)
1. Migrations réversibles `agent_conversations`, `agent_messages`, `agent_feedback`, `agent_settings` (+`encrypts`).
2. Modèles + specs de confidentialité (auteur seul).
3. `Agent::Context` immuable, `Agent::FakeGateway`, `Agent::ModelGateway` (garde-fou d'environnement §7).
4. `Agent::Runner` (boucle explicite, limites 8 tours/20 outils/60 s/tokens, 3 erreurs d'outil).
5. Panneau Turbo Stream + Stimulus (état vide, arrêt, aria-live, raccourci), rendu Markdown assaini (ajouter une gem ou un rendu maison à valider).
6. API `/api/v1/agent/…` via ApiClient + scopes.
7. Interrupteur d'urgence + `feature_agent` + quotas basiques.
8. Spec système (ouverture, question, arrêt, avis).

A02 Catalogue d'outils (§5)
1. `Agent::Tools::Base` (schéma strict, permission, `call`, `format`, refs, troncature 20 Ko, montants en chaînes).
2. Résolution id → modèle, limites, curseur (adaptateurs minces au-dessus des services; corriger les filtres ignorés ou les masquer).
3. Un outil par commit, avec spec de parité contre le rapport: `get_company_context`, `search_accounts`, `search_partners`, `get_trial_balance`, `get_ledger`, `get_journal_entry`, `get_aged_balance`, `list_unreconciled`, `get_bank_reconciliation`, `get_financial_statements`, `get_vat_return`, `get_dashboard_kpis`, `get_consistency_findings`, `get_audit_trail`, `search_documents` (`get_budget_vs_actual` selon D11).
4. Spec d'absence d'écriture (liste blanche + garde dynamique).
5. `agent_tool_calls`, audit R18 (acteur = agent via payload).

A03 Sécurité (§6)
1. Policies par outil + rejet de `company_id`, droits revérifiés à chaque appel.
2. Contenu non fiable balisé, troncature `free_text`, détecteur heuristique, `agent_security_events`.
3. Validation de la réponse finale (URL, secrets, citations).
4. Isolation en parallèle, aucun cache partagé.
5. Corpus d'injection initial (40), rejeu avec FakeGateway.

A04 Confidentialité (§7)
1. `agent_consents` versionné, écran d'activation propriétaire.
2. Migration `partners.is_natural_person` (nullable, inconnu = personne physique) — **modifie une table existante, à valider**.
3. `Agent::Redactor` (classes de données, pseudonymisation réversible, IBAN, TVA), détection dans les messages utilisateur.
4. « Voir ce qui a été envoyé », rétention (job de purge, file dédiée), export/effacement par personne.
5. `DATA_PROCESSING.md` + questions juridiques dans `QUESTIONS.md`.

A12 socle (§15)
1. `agent_evals`, `agent_eval_runs`, `Agent::Evals::Runner` (`bin/rails agent:evals`), évaluateurs déterministes.
2. 30 premiers cas sur le jeu de référence existant (attendus calculés indépendamment).
3. Manifeste de version (hash) stocké par message.

Fin de P0: critères du §3, rejeu complet sécurité/confidentialité, `docs/dev/agent/A01.md…A04.md`.

## 7. Points bloquants avant de coder
- Réponses D1, D2, D9, D11.
- Validation de l'ajout de `partners.is_natural_person` et de `entries.created_via`.
- Décision sur l'extraction `CreateDraftEntry` (avant A07).
- Ajouts de gems: client LLM, rendu Markdown assaini, mutant, i18n-tasks.


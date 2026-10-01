# Audit — Fonctions transverses F01 à F13 (§17.2)

Réalisé à partir de `docs/dev/features/spec.md` et `docs/dev/reports/spec.md` (lus intégralement), de `docs/dev/reports/00-audit.md`, `QUESTIONS.md`, `docs/dev/HANDOFF_next_steps.md` et d'une exploration du dépôt (état au commit `4eccee8`, branche `development`). **Aucun fichier de code n'a été modifié.**

## 0. Lecture rapide

- Le dépôt est **bien plus avancé que ne le suppose la spec**. Les rapports R01 à R20 existent en v1 (y compris R18 chaîne de hachage, R19 contrôles, R20 liasse), ainsi qu'une bonne part de F04, F06, F07 (récurrentes de *factures* seulement), F09, F10 et F11 sous une forme différente.
- **Trois trous structurels** conditionnent tout le reste :
  1. **Aucun contrôle d'accès fin ni verrouillage de période.** Les droits reposent sur un rôle global (`users.role`) et un rôle par société (`user_entities.role`), mêlés selon les policies. Il n'existe ni permissions, ni `period_locks`, ni trigger de verrouillage. Seul le statut `closed` d'un exercice existe, et il n'est vérifié que par quelques services.
  2. **Aucun service unique d'écriture comptable.** Une douzaine de services créent eux-mêmes `JournalEntry` et `JournalEntryLine` (§2). `Accounting::PostJournalEntry` ne s'occupe que de la validation d'un brouillon.
  3. **Aucune gestion documentaire** (F03) : Active Storage n'est branché que sur deux pièces jointes de `Invoice`. Il n'y a pas de table `documents`, pas de boîte de réception, pas d'extraction et pas de recherche plein texte.
- **Nommage** : comme pour l'audit des rapports, la spec utilise des noms hypothétiques (`companies`, `company_id`, `reconciliations`, `journal_entries`). Le code réel utilise `entities`, `entity_id`, `accounting_letterings`, `accounting_journal_entries`, etc. Aucun extrait de la spec ne se recopie tel quel.
- **Langue** : la spec exige fr, nl et en (§2.5). L'application est en **anglais seulement** pour l'interface (règle projet, mémoire `feedback_language`). `config/locales` contient `en.yml` (475 lignes) et `fr.yml` (240 lignes), sans `nl`. À arbitrer (§5, point 11).

## 1. Audit par fonction

Légende : ✅ existe · 🟡 partiel ou sous une autre forme · ❌ absent.

### F01 — Droits par rôle et verrouillage de périodes (P0)

| Élément de la spec | État | Constat |
|---|---|---|
| `roles`, `permissions` fines, rôles personnalisés | ❌ | `users.role` est un enum global `{admin, accountant, manager, auditor, budget_user}`. `user_entities.role` est un enum par société `{admin, accountant, manager, auditor}`. Pas de table `roles` ni de permissions (`entries.post`, etc.). |
| `memberships` (accès valable du/au, journaux autorisés, expiration) | 🟡 | `user_entities` (actif/inactif, rôle) joue le rôle de membership, sans dates de validité ni restriction par journal. |
| Policies côté serveur | 🟡 | 18 policies sous `app/policies/accounting/`. `ApplicationPolicy` s'appuie sur l'appartenance à la société (`membership`). Mais `InvoicePolicy`, `FiscalYearPolicy` et `JournalEntryPolicy#post?/reverse?` utilisent `user.admin? \|\| user.accountant?` (rôle **global**). Un utilisateur accountant dans la société A l'est donc aussi dans la société B. C'est contraire au critère « les droits ne se mélangent jamais ». |
| `period_locks` | ❌ | Seul l'exercice a un statut (`open`, `pre_closing`, `closed`). Pas de verrou mensuel, TVA ou fin d'exercice. `VatDeclaration` (submit/accept) joue le rôle de période TVA sans verrou. |
| Trigger de verrouillage SQL | ❌ | Les triggers existants : `enforce_double_entry`, `prevent_audit_log_modification`, `prevent_bank_reconciliation_report_modification`. Un posté est protégé **au niveau modèle seulement** (`Accounting::Immutable`, callbacks AR). Un `update_all`/SQL direct le contourne. |
| Refus d'écriture dans une période verrouillée par le service | 🟡 | Aucun contrôle dans `PostJournalEntry`. Seuls `ReverseJournalEntry`, `PostDepreciation`, `BookAccrual`, `DisposeFixedAsset` et `ReverseAccrual` testent `fiscal_year.closed?`. Je n'ai trouvé aucun garde équivalent dans `JournalEntriesController` (à confirmer par un test en début de F01). |
| Quatre yeux (`four_eyes`) | ❌ | Pas de `created_by` sur `journal_entries` (traçable seulement par PaperTrail `whodunnit`). |
| TOTP obligatoire | 🟡 | **Passkeys WebAuthn + codes de récupération** existent (`webauthn_credentials`, `recovery_codes`). Pas de TOTP. Devise `lockable` (verrouillage de compte), `timeoutable` et `trackable` sont actifs. Le seuil de 5 échecs n'a pas été vérifié. |
| Auditeur externe (durée limitée, filigrane PDF) | 🟡 | Le rôle `auditor` existe. Pas d'expiration d'accès, pas de filigrane. |
| Jetons d'API bornés par les droits du propriétaire | 🟡 | `ApiClient` (table `api_clients`) : clé hachée, `scopes[]`, `last_used_at`. Les scopes sont par client, pas rattachés à un utilisateur. La notion « ne dépasse jamais les droits du propriétaire » n'a pas de sens aujourd'hui, car il n'y a pas de propriétaire. Un JWT hérité (déprécié) donne un accès complet. |
| Dernier propriétaire non retirable | ❌ | Non vérifié dans `UserEntity`. |
| Audit des changements de droits, connexions, échecs | 🟡 | `AuditTrailed` journalise les modèles qui l'incluent (liste à vérifier). Les connexions et échecs ne sont pas journalisés dans `accounting_audit_logs` (Devise `trackable` seulement). |

**Migrations nécessaires** : `roles`, `role_permissions` (ou colonne jsonb), `period_locks`, colonnes `memberships` (`valid_from`, `valid_until`, `journal_ids`), `journal_entries.created_by_id` et `posted_by_id` (+ backfill depuis PaperTrail), `entities.four_eyes` et `four_eyes_threshold`, trigger de verrouillage sur `accounting_journal_entry_lines` et `accounting_journal_entries`, colonne TOTP sur `users`.
**Risques** :
- **Élevé** : le trigger doit laisser passer la transition légitime posted→reversed et les écritures de clôture ou de migration (fenêtre contrôlée). Il faut l'écrire avec une variable de session (`SET LOCAL ledgerflow.lock_override`).
- **Élevé** : remplacer les `user.admin? \|\| user.accountant?` globaux par la matrice change le comportement pour tous les contrôleurs, d'où l'intérêt de la matrice unique `Permissions::MATRIX`.
- **Moyen** : le backfill de `created_by_id` est impossible pour les écritures sans version PaperTrail (laisser NULL).
- Préserver les rôles actuels : traduire `admin/accountant/manager/auditor/budget_user` vers les 5 rôles de la spec sans régression sur les ~370 fichiers de specs.

### F03 — Gestion documentaire (P0)

| Élément | État | Constat |
|---|---|---|
| Stockage Active Storage | 🟡 | Tables `active_storage_*` présentes. Seul `Invoice` porte `has_one_attached :ubl_document` et `:pdf_document`. Service `:local` en production (volume `ledgerflow_storage`, à sauvegarder, cf. `docs/dev/peppol-received-documents.md`). Pas de chiffrement au repos. |
| `documents`, `document_links` | ❌ | Rien. Le drill-down « pièce » de R02 reste sans fondation (déjà noté dans l'audit des rapports). |
| Boîte de réception, ActionMailbox, ZIP | ❌ | ActionMailbox non installé. |
| Extraction (texte PDF, OCR, UBL), propositions | ❌ | `Peppol::ReceiveInvoice` lit déjà l'UBL pour créer un brouillon (réutilisable pour l'extracteur UBL). |
| Recherche plein texte (`unaccent`, `tsvector`) | ❌ | `db/structure.sql` ne contient **aucune extension** (`pg_trgm` et `unaccent` à activer, ce qui est aussi requis par F02 règle 4). |
| Intégrité (`documents:verify`), rétention, `legal_hold` | ❌ | |
| Contrôle MIME réel, antivirus | 🟡 | Contrôle `%PDF` et 15 Mo pour le PDF embarqué Peppol uniquement. |
| Lien signé avec scope société | 🟡 | `InvoicesController#document` (mêmes droits que la fiche, pas d'URL publique). À généraliser. |

**Migrations** : extensions `unaccent`, `pg_trgm` ; `documents`, `document_links` ; colonne `tsvector` + index GIN ; migration des `ubl_document`/`pdf_document` existants vers `documents` (à décider : liens plutôt que copie).
**Risques** : moyen. Tables neuves, mais la reprise des pièces Peppol existantes ne doit rien déplacer physiquement sans accord. Le volume `ledgerflow_storage` doit être sauvegardé avant tout.

### F02 — Import CODA et rapprochement bancaire (P0)

| Élément | État | Constat |
|---|---|---|
| Parseur CODA | ❌ | Aucune trace de CODA dans le code. Existent : **CAMT.053** (`ImportCamtStatement`, namespace `camt.053.001.02`) et **CSV** (`ImportCsvStatement`). |
| `bank_statements` (solde d'ouverture/clôture, empreinte du fichier) | ❌ | `accounting_bank_transactions` est plate (`bank_account_id`, `journal_entry_id`, `amount`, `description`, `reference`, `raw_data`). Pas de contrepartie, IBAN, communication structurée ni code d'opération en colonnes. Le parseur CAMT ignore l'IBAN de la contrepartie (note `ponytail:` dans `MatchBankTransaction`). |
| Idempotence | 🟡 | Dédoublonnage par `(bank_account, reference)` seulement. Ni empreinte du fichier ni empreinte de ligne. Un import n'est pas atomique par fichier de façon documentée (transaction oui, mais pas de rejet avec la liste des lignes fautives). |
| `bank_rules`, `import_batches` | ❌ | |
| Moteur de rapprochement | 🟡 | `MatchBankTransaction` (lecture seule) : lot SEPA (`message_id`), facture par communication structurée (modulo 97 : `Accounting::StructuredCommunication`), paiement groupé de factures, frais (`Bank::Simulator::BankFees`). `AcceptBankSuggestion`, `ReconcileBankTransaction`, `PayInvoiceFromTransaction` (fournisseur, avec devise). Manques : règles 2 (n° de facture), 3 (IBAN), 4 (similarité), score numérique, règles configurables, virements internes par compte de transit. |
| Écriture de paiement en brouillon par défaut | ❌ | À vérifier : `CreateBankJournalEntry` / `AcceptBankSuggestion` créent-ils un brouillon ou valident-ils ? (à lire en F02.) |
| R06 (rapprochement figé) | ✅ | `BankReconciliationReport` figé et immuable (trigger). Le chaînage de relevés n'est pas implémentable sans `bank_statements` (déjà signalé). |
| Permissions `bank.import` / `bank.match` | ❌ | Dépend de F01. |

**Migrations** : `bank_statements`, `bank_statement_lines` (ou extension de `bank_transactions` : `statement_id`, `counterparty_name`, `counterparty_iban`, `structured_communication`, `bank_reference`, `fingerprint`, `status` étendu), `bank_rules`, `import_batches`, empreintes SHA-256.
**Risque élevé** : `accounting_bank_transactions` est consommée par R06, le simulateur, l'import CSV/CAMT et le paiement fournisseur. Décision à prendre : **étendre la table existante** plutôt que créer `bank_statement_lines` en parallèle (deux sources de vérité, comme pour la TVA).
**Pas de fichier CODA réel** dans le dépôt : il faut en demander des échantillons anonymisés (§16 de la spec) avant d'écrire le parseur.

### F04 — Lettrage assisté (P1)

| Élément | État | Constat |
|---|---|---|
| Lettrage total | ✅ | `Accounting::LetterLines` (organizer : `PostFxAdjustment`, `ValidateLettering`, `CreateLettering`, `PayLetteredInvoices`), `UnletterLines`. Codes `AA`, `AB`, … par compte (`Lettering.next_code_for`). |
| Lettrage partiel | ✅ | `accounting_line_allocations` (`debit_line_id`, `credit_line_id`, `amount`, `allocated_on`), `AllocateLines`, `RemoveAllocation`. `amount_residual` maintenu par `JournalEntryLine.resync_amount_residual!`. |
| `reconciliations.kind/reason/unreconciled_by`, délettrage avec motif | ❌ | Le délettrage supprime/annule le lettrage sans trace d'acteur ni motif (le modèle `Lettering` n'a pas d'acteur ; l'audit `AuditTrailed` est présent). |
| `reconciliation_suggestions`, `Suggester`, job nocturne, `auto_reconcile_exact` | ❌ | R05 donne déjà des « groupes équilibrés non lettrés » en lecture seule. |
| Verrou d'enregistrement (concurrence) | ❌ à vérifier | Pas de `with_lock` constaté dans `LetterLines`. |
| Nom des services | 🟡 | La spec impose `Ledger::Reconcile/Unreconcile` comme **seuls** modificateurs de `amount_residual`. Aujourd'hui 5 endroits appellent `resync_amount_residual!` (dont `PayInvoiceFromTransaction`). |
| Permission `reconciliations.cross_partner`, `unreconcile_locked` | ❌ | Dépend de F01. |

**Migrations** : `letterings.kind`, `reason`, `unreconciled_at`, `unreconciled_by_id`, `reconciliation_suggestions`. **Risque faible à moyen** (colonnes ajoutées, aucune donnée à modifier).

### F05 — Migration depuis WinBooks (P1)

| Élément | État | Constat |
|---|---|---|
| Format canonique, adaptateurs, staging `migration_*` | ❌ | Rien. |
| Soldes d'ouverture + factures ouvertes (CSV) | ✅ | `Accounting::ImportOpeningBalances` : vérification à blanc, import tout ou rien, premier exercice, une seule fois, compte d'attente 499000, `source_type = "Accounting::OpeningBalance"`. C'est le seul mode « soldes d'ouverture seulement » de la spec, et il est CSV maison (pas WinBooks). |
| Historique complet, lettrages, immobilisations, retour arrière | ❌ | |
| `source_system`, `source_id`, `migration_batch_id`, `legacy_number`, `imported_objects` | ❌ | `external_ref`, `source_type`, `source_id` existent sur `journal_entries`, mais pour un autre usage (factures API, documents sources). |
| Fichier WinBooks de référence | ❌ | **Aucun dossier WinBooks dans le dépôt.** La spec exige que l'utilisateur en fournisse un. Aucune ligne de code ne doit être écrite avant. |

**Migrations** : tables `migration_batches`, staging, `imported_objects`, colonnes de traçabilité. **Risque élevé** : volume (500 000 lignes en moins de dix minutes) et dépendance à F01 (fenêtre de verrouillage) et à `PostEntry`. Rappel : aucune donnée existante ne doit être modifiée sans accord.

### F06 — Peppol (P1) — audit préalable exigé par la spec (« Étape 0 »)

L'étape 0 de la spec demande un `F06-audit.md` séparé et un arrêt avant de toucher au code existant. En voici l'état de départ, à détailler dans ce fichier le moment venu :

| Élément | État | Constat |
|---|---|---|
| Adaptateurs d'Access Point | ✅ | `Peppol::AccessPoint::{Simulator, Digiteal, B2brouter}` (interface `Base`), choix par société (`entities.peppol_access_point`, credentials chiffrés, `peppol_webhook_token`). **La spec dit « Digiteal »**, mais le dernier choix de l'utilisateur est B2Brouter (HANDOFF §3c). L'adaptateur Digiteal est « écrit de mémoire, non validé ». |
| Envoi UBL | ✅ | `SendInvoice` : `ValidateSendable` → `BuildUblXml` → `SendViaAccessPoint` → `HandleDeliveryStatus`. Statuts livré/échec, historique `accounting_peppol_events`. |
| Validation schematron avant envoi | ❌ | Non faite (« non vérifiable hors ligne »). Décision à prendre avec l'utilisateur (service du fournisseur d'accès ou schematron local). |
| Réception | 🟡 | `ReceiveInvoice` crée un brouillon fournisseur, garde l'XML d'origine et le PDF embarqué, dédoublonne par fournisseur + numéro. **B2Brouter : la réception n'est pas gérée.** |
| Webhook authentifié | 🟡 | `POST /peppol/webhooks/:token` (token par société). Signature HMAC vérifiée avec B2Brouter d'après le HANDOFF. À confirmer pour chaque adaptateur. |
| `peppol_messages`, `peppol_participants`, `supplier_defaults`, `vat_category_mappings` | ❌ | Les événements sont dans `accounting_peppol_events`. Le participant est une colonne de `entities`. Catégories UBL gérées en dur (S/Z/E/AE/K/G) dans `UblInvoiceBuilder`. |
| `needs_review`, contrôles de totaux, création du fournisseur « à valider » | ❌ | |
| Notes de crédit | ✅ | Émission (381 + `BillingReference`) et réception. |
| Devise étrangère | ✅/🟡 | Les factures sont multi-devises. La spec les met en `needs_review` jusqu'à F11, ce qui est dépassé. |
| Interdiction de modifier l'intégration Digiteal sans accord | ⚠ | Règle de CLAUDE.md pour les fonctions transverses (§17.1). Elle vise Digiteal. Les modifications F06 doivent passer par un accord explicite. |

**Migrations** : `peppol_messages`, `supplier_defaults`, `vat_category_mappings` (ou réutiliser `accounting_vat_codes`). **Risque moyen**, car toucher à un flux déjà vérifié dans le sandbox B2Brouter.

### F07 — Écritures récurrentes, modèles, extourne (P1)

| Élément | État | Constat |
|---|---|---|
| Récurrentes | 🟡 | **Seulement des factures** : `RecurringInvoice`, `RunRecurringInvoices`, `GenerateRecurringInvoicesJob` (quotidien, `config/recurring.yml`), rattrapage de 12 occurrences, brouillon jamais posté automatiquement, date calculée depuis `start_on`. Rien pour les OD (loyer, assurance, dotation). |
| `entry_templates`, `recurring_entries`, `recurring_runs` (clé d'unicité) | ❌ | Pas de table `recurring_runs` : l'idempotence repose sur `runs_count` et `last_run_on`, pas sur une clé unique par échéance. Deux instances simultanées ne sont pas garanties. |
| Indexation annuelle, aperçu des 12 échéances, `feeds_cash_forecast` | ❌ | `accounting_cash_forecast_items` existe pour R14. |
| `Ledger::ReverseEntry` | ✅/🟡 | `ReverseJournalEntry` : motif obligatoire, `reversal_of_id`, une seule extourne (`has_one :reversal`), refus si exercice clos, lettrée ou avec source. Manques : `reversed_by_entry_id` (pas de lien bidirectionnel en colonne, seulement `has_one`), `auto_reverse_on`, date choisie dans la première période ouverte, **le refus pour une écriture lettrée au lieu du délettrage préalable confirmé**, régularisation TVA. `ReverseAccrual` fait une extourne planifiée propre aux régularisations. |
| Bouton « Dupliquer » | 🟡 | Existe pour les **factures** (`DuplicateInvoice`), pas pour les écritures. |

**Migrations** : `entry_templates`, `recurring_entries`, `recurring_runs` (unique `(recurring_id, due_date)`), `journal_entries.auto_reverse_on`. **Risque faible** (tables neuves). Le principal risque est d'aligner `ReverseJournalEntry` sur la spec sans casser ses appelants (factures, lots de paiement, régularisations).

### F08 — Tâches et commentaires (P2)

❌ **Entièrement absent.** `noticed` est dans le Gemfile, mais aucun notifier ni modèle de tâche, de commentaire ou de notification n'existe (`app/notifiers` absent). Le lien signé externe pour un tiers dépend de F03. **Migrations** : `tasks`, `comments`, `notifications` (ou tables `noticed`). **Risque faible**, mais la visibilité « suit celle de la cible » impose une policy par type de cible, donc dépend de F01.

### F09 — Relances clients (P2)

| Élément | État | Constat |
|---|---|---|
| Relances | ✅ en manuel | `PaymentRemindersController`, `OverdueReminders` (une ligne par client, niveaux 1 à 3, délai de 14 jours), `SendPaymentReminder`, `PaymentReminderJob`, `PaymentReminderMailer` (PDF des factures en pièce jointe), tables `accounting_payment_reminders` et `_items`. Aperçu et validation humaine : oui (envoi sur action). |
| `dunning_policies` (paliers et textes paramétrables, trois langues) | ❌ | Niveaux et textes en dur (anglais). |
| Litige, promesse de paiement, `dunning_level`, `last_dunned_at` sur les lignes | ❌ | |
| Intérêts et indemnités paramétrables | ❌ | Rien n'est codé (conforme à la règle « aucun taux codé en dur »). |
| Relevé de compte joint, tâche de suivi F08, rebonds, `auto_send_level_1` | ❌ | Dépend de F08 et de la config SMTP de production (non faite). |

**Migrations** : `dunning_policies`, colonnes litige et promesse. **Risque faible à moyen** : la structure `payment_reminders` actuelle devra être alignée sur `dunning_runs/items` plutôt que doublée.

### F10 — Clôture d'exercice guidée (P2)

| Élément | État | Constat |
|---|---|---|
| Liste de contrôles | 🟡 | `ClosingChecklist` : 11 contrôles (brouillons, dotations, équilibre, factures brouillon, banque non rapprochée, créances > 90 jours, avoirs non alloués, réévaluation devises, déclarations TVA, revue TVA immobilisations, exercice suivant) avec statut bloquant/avertissement/info. C'est un sous-ensemble des 18 étapes. |
| `closing_runs`, `closing_steps`, statuts, acquittement, commentaires | ❌ | Rien n'est persisté. Les contrôles s'évaluent en direct (ce que la spec demande), mais sans acquittement ni étapes manuelles. |
| Écritures de clôture en brouillon puis validation par lot | 🟡 | `CloseFiscalYear` (organizer) génère l'écriture de clôture et la valide via `PostJournalEntry` (correction du défaut brouillon signalée dans le HANDOFF). **Contradiction avec la spec** : celle-ci veut des brouillons validés par un humain en lot. |
| À-nouveaux détaillés avec `origin_line_id` | 🟡 | `CarryForwardBalances` / `ComputeCarryForwardBalances` existent. `origin_line_id` n'est pas dans `journal_entry_lines`. |
| Instantané figé (`closing_snapshots`) + liasse | 🟡 | `ClosingBundle` (R20) : ZIP de PDF + manifeste SHA-256 + `verify`. Pas de `closing_snapshots`. |
| Réouverture, recalcul des à-nouveaux, approbation avec `four_eyes`, fenêtre de verrouillage | ❌ | Dépend de F01 et F07. |
| Étape 12 (réévaluation) | ✅ | `ProposeRevaluationEntry` (brouillon + extourne planifiée, perte latente en 651200/499100, gains non comptabilisés). |

**Migrations** : `closing_runs`, `closing_steps`, `closing_snapshots`, `journal_entry_lines.origin_line_id`. **Risque moyen** : orchestrer sans recalculer, en réutilisant `ClosingChecklist`, `ClosingBundle` et les requêtes de rapports.

### F11 — Multi-devises et écarts de change (P2) — **contradiction de convention**

| Élément | État | Constat |
|---|---|---|
| **Convention de taux** | ⚠ **CONTRADICTION** | La spec impose « unités de devise pour **1 EUR** », EUR = devise ÷ taux. Le code est à l'inverse : `ExchangeRate` documente « **EUR pour 1 unité** de `currency` » (même convention que les factures). Les lignes ont `exchange_rate numeric(10,6)` et `amount_currency numeric(15,2)` (la spec veut 8 décimales et `numeric(18,4)`). |
| Taux | 🟡 | `accounting_exchange_rates` (par société, date, devise, `rate > 0`, `rate_for` = dernier taux antérieur ou égal). Saisie manuelle uniquement : pas d'import BCE ni InforEuro, pas de `type`, de `source` ni de motif d'écrasement. Le repli « dernier taux connu » est le comportement par défaut de `rate_for`, **contraire** à « jamais d'usage silencieux ». Le rapport de réévaluation affiche « No rate » plutôt que de deviner. |
| `currencies` (décimales 0/2/3) | ❌ | Tout est à 2 décimales. |
| Écart réalisé | 🟡 | `PostFxAdjustment` (dans `LetterLines`) et `PayInvoiceFromTransaction` (par paiement, comptes 651200/751100). La spec veut une écriture `system` validée automatiquement et défaite avec le lettrage. À comparer. |
| Réévaluation | ✅ | Voir F10. |
| Comptes en devise, `rate_policy`, taux manquants refusant la validation | ❌ | |

**Migrations** : `currencies`, extension de `exchange_rates` (type, source), éventuellement `numeric(18,4)` et 8 décimales. **Risque élevé** : changer la convention ou la précision d'un taux déjà utilisé touche toutes les factures en devise, les écritures et la réévaluation. **À trancher avec l'utilisateur avant toute ligne de code** (§5, point 3).

### F12 — Multi-dossiers et consolidation (P3)

| Élément | État | Constat |
|---|---|---|
| `organizations`, instantanés de santé des dossiers | ❌ | Un utilisateur peut appartenir à plusieurs sociétés (`user_entities`), avec un sélecteur (`entities#switch`). |
| Consolidation | ❌ | Rien (le seul « consolidat… » du dépôt est une référence documentaire). |

**Risque** : le multi-tenant repose sur `acts_as_tenant :entity`. Le tableau de bord de portefeuille doit éviter toute requête qui traverse plusieurs sociétés (critère 2). Dépend de F11 et de tous les rapports.

### F13 — Import, export et API (P3)

| Élément | État | Constat |
|---|---|---|
| API REST | 🟡 | `/api/v1` : `ping`, `invoice_events`, `incoming_invoices` (claim, documents), `journal_entries` (lecture), `invoices` (upsert par `external_ref`, annulation), `partners`, `projects/:id/accounting_summary`. **Conçue pour BudgetFlow** et fermée aux autres sociétés (`entity.budgetflow?`). Voir `docs/dev/api/inbound-api.md`. |
| Authentification | 🟡 | Clés `lf_…` (`ApiClient`, scopes, journal `api_requests`), JWT hérité déprécié. Pas de jetons personnels avec rotation par utilisateur. Une rotation existe pour les clients (`POST …/rotate`). |
| Limitation de débit | ✅ | `Rack::Attack`, 300/min par IP et par clé (la spec veut 60/min par jeton, et des en-têtes explicites). Réponse 429 JSON avec `Retry-After`. |
| OpenAPI 3.1 / rswag, `problem+json`, `ETag/If-Match`, `Idempotency-Key`, pagination par curseur | ❌ | Les gems rswag et openapi sont absents. L'idempotence existe par `external_ref` pour les factures. |
| Webhooks sortants signés | ❌ | Un flux d'événements en lecture (`GET /invoice_events`) existe, pas de webhooks. |
| Imports CSV/XLSX guidés | 🟡 | Uniquement `ImportOpeningBalances` et import CSV de relevés. Pas de gabarits de mapping. |
| Exports | 🟡 | CSV/XLSX/PDF par rapport (`Reports::Exporters::*`), `AuditExport`, `ClosingBundle`, `FilingData`. Pas de sauvegarde complète ZIP avec pièces. |
| `POST /api/v1/journal_entries` | ⚠ | **Supprimé volontairement** (commit `86fd123` : « third parties inject invoices, not ad-hoc entries »). La spec F13 veut des écritures par API en brouillon. Décision à reconfirmer. |

**Risque** : moyen. La plupart des éléments sont nouveaux, mais l'API actuelle sert BudgetFlow : ne jamais la casser (règle « ne jamais modifier BudgetFlow », et `v1` doit rester compatible).

## 2. État réel des mécanismes transverses

### 2.1 Services d'écriture comptable

La spec veut `Ledger::PostEntry`, `ReverseEntry`, `Reconcile`, `Unreconcile` comme **seuls** points d'écriture. Réalité :

- **Validation** : `Accounting::PostJournalEntry` (organizer : `ValidateBalance`, `AssignSequenceNumber`, `LockEntry`, `UpdateAccountBalances`, `WriteAuditLog`, `BroadcastTurboUpdate`). Elle ne vérifie ni le verrouillage de période, ni le statut de l'exercice, ni les droits.
- **Extourne** : `Accounting::ReverseJournalEntry`.
- **Création directe de `JournalEntry` / `JournalEntryLine` (hors specs)**, à regrouper derrière un service unique :
  - `Accounting::Actions::GenerateInvoiceJournalEntry`, `PayFromCash`, `PostFxAdjustment`, `ReviewFixedAssetVat`, `GenerateClosingEntry`, `CreateBankJournalEntry`, `CreateOpeningBalanceEntry`
  - `Accounting::PostDepreciation`, `DisposeFixedAsset`, `BookAccrual`, `ReverseAccrual`, `ProposeRevaluationEntry`, `ImportOpeningBalances`, `PayInvoiceFromTransaction` (deux sites)
  - `JournalEntriesController` (saisie manuelle, avec `accepts_nested_attributes_for :lines`)
  - `lib/seeders/reference_ledger_seeder.rb` (graines, hors production)
- **Contournement structurel** : la contrainte `enforce_double_entry` oblige plusieurs services à exécuter `SET CONSTRAINTS enforce_double_entry DEFERRED`. Un service unique devrait encapsuler cela.
- **Recommandation** : introduire `Ledger::PostEntry` en façade (garde de période, fenêtre contrôlée, `created_by`, audit), puis migrer les ~15 appelants un par un derrière des specs de caractérisation. Ne pas réécrire la logique de génération des écritures de factures.

### 2.2 Lettrage

Complet et consommé par R04/R05 (voir F04). `amount_residual` : un seul module (`resync_amount_residual!`) mais 5 appelants, dont un hors des services de lettrage.

### 2.3 Verrouillage de périodes

Inexistant au sens de la spec (voir F01). Aujourd'hui : `Accounting::Immutable` (modèle) + statut d'exercice vérifié ponctuellement.

### 2.4 Audit

Trois couches coexistent : (1) `accounting_audit_logs` en ajout seul, **chaîne SHA-256 par société**, trigger `prevent_audit_log_modification`, verrou consultatif par société, `reason`, `request_id`, `api_client` ; `AuditVerifier`, `rake audit:verify` ; (2) concern `AuditTrailed` qui y écrit un enregistrement par création, modification ou suppression avec le diff `payload["changes"]` ; (3) **PaperTrail** (`versions`, concern `Auditable`) en parallèle. R18 est donc largement fait, et la mention de l'audit des rapports (« deux mécanismes parallèles ») reste valable. **Manque pour F01-F13** : connexions et échecs, changements de droits, exports (à vérifier), toute action des nouvelles fonctions.

### 2.5 Stockage de fichiers

Active Storage local, deux pièces sur `Invoice`. Pas de chiffrement, pas de lien signé générique, pas de S3. Le volume Docker doit être sauvegardé (`docs/dev/backup_restore.md`, `bin/backup`).

### 2.6 Authentification

Devise (lockable, timeoutable, trackable), passkeys WebAuthn, codes de récupération. Pas de TOTP. Throttle de connexion : 5 requêtes par 20 secondes par IP. API : clés `lf_…` et JWT hérité.

### 2.7 Tâches de fond et planification

Solid Queue dans Puma. `config/recurring.yml` : une seule tâche récurrente (factures récurrentes). `ConsistencyCheckJob`, `InvoiceEmailJob`, `PaymentReminderJob`. Pas de réessais « 3 tentatives avec attente croissante » déclarés de façon uniforme (à vérifier job par job).

### 2.8 Drapeaux de fonctionnalité

Absents (pas de Flipper). Existe un drapeau maison : `entities.budgetflow_enabled`, et `config.x.peppol_simulator_allowed`. La spec demande `feature_f01` à `feature_f13` par société.

### 2.9 Tests

368 fichiers de specs (`spec/`) : `invariants/`, `performance/`, `system/`, `policies/`, `requests/`, etc. Exemple partagé existant : `entity scoped report` (la spec veut un `company scoped` pour **tous** les endpoints et jobs). `Bullet.raise = true` global. Pas de Mutant, pas de `i18n-tasks`, pas de rswag.

## 3. Intégration Peppol (F06) et API JWT (F13) — résumé

- **Peppol** : voir F06. Trois adaptateurs, B2Brouter retenu par l'utilisateur, Digiteal non validé, simulateur refusé hors dev/test, réception B2Brouter non gérée, validation schematron absente.
- **API** : voir F13. Clés `lf_…` avec scopes + JWT hérité. Entièrement tournée vers BudgetFlow. Contrat documenté (`inbound-api.md`).

## 4. Dépendances entre fonctions qui diffèrent du §3 de la spec

1. **F01 est bloquant pour presque tout**, et deux de ses éléments devraient précéder le reste : (a) la façade `Ledger::PostEntry` avec garde de période, (b) la matrice de permissions. Sans elles, F02 à F13 écrivent des droits et des écritures dans le vide.
2. **F04, F06, F07, F09, F10 et F11 ne partent pas de zéro.** Leur effort réel est de **mise en conformité** d'un existant qui fonctionne (et dont les décisions ont été validées par l'utilisateur). C'est un tout autre profil de risque que celui d'une fonction neuve : la régression plutôt que l'omission.
3. **F11 ↔ F04 ↔ F07** : la spec place F11 après F04 et F07, mais l'existant fait déjà de l'écart de change au lettrage. La convention de taux (point 3) doit être tranchée **avant** de toucher F04.
4. **F03 ↔ F02** : la spec place F03 en premier, c'est cohérent. Mais F02 n'a besoin que du stockage et du lien signé, pas de l'extraction ni de l'OCR. Livrer d'abord le noyau de F03 (table `documents`, lien signé, rattachement) suffirait à débloquer F02, l'extraction pouvant suivre.
5. **F08 ↔ F09** : les relances existent déjà sans F08. La tâche de suivi automatique est un ajout ultérieur et non un prérequis.
6. **F10 dépend de F07** (extourne planifiée, `Ledger::ReverseEntry` conforme) alors que l'existant a déjà `ReverseAccrual` et `ProposeRevaluationEntry` autonomes.
7. **F13 (jetons personnels)** dépend de F01 pour avoir un « propriétaire » dont les droits bornent le jeton.

## 5. Points ambigus, contradictoires ou incompatibles avec le code

1. **Nommage** : tout est à traduire (voir §0). Les chemins de la spec (`docs/features/…`) correspondent à `docs/dev/features/…` dans ce dépôt.
2. **CODA vs CAMT** : l'existant lit CAMT.053 et CSV, pas CODA. Le CODA reste nécessaire pour les banques belges qui n'exportent que ce format. Sans échantillons réels, aucun parseur fiable. À confirmer : **CODA est-il toujours demandé ?**
3. **Convention de taux de change** (F11) : spec = devise pour 1 EUR ; code = EUR pour 1 devise. Il faut choisir (a) adapter la spec au code (recommandé : aucune donnée à convertir, aucun risque de double inversion) ou (b) migrer. Dans les deux cas, ajouter le test « pas d'inversion » demandé par la spec.
4. **Clôture : brouillon ou validé ?** La spec veut des écritures de clôture en brouillon validées en lot par un humain. `CloseFiscalYear` valide aujourd'hui l'écriture de clôture elle-même. Idem pour l'écart de change réalisé (F11 : validé automatiquement par exception) et les règles de la spec §2.4.
5. **Écritures par API** : la spec F13 veut `POST /entries` en brouillon ; un commit récent l'a retiré volontairement.
6. **Verrouillage et exercices** : trois états d'exercice (`open`, `pre_closing`, `closed`) contre la logique `period_locks`. `pre_closing` doit être cartographié (comme déjà noté dans l'audit des rapports).
7. **Deux systèmes d'audit** (PaperTrail et `accounting_audit_logs`) : la spec F01 demande de journaliser « tout », mais ne dit pas lequel. Recommandation : `accounting_audit_logs` (chaîne de hachage) comme seule source pour les nouvelles fonctions, PaperTrail laissé tel quel.
8. **Droits globaux et par société** : `users.role` (global) cohabite avec `user_entities.role`, et certaines policies utilisent le global. C'est un défaut de sécurité latent à corriger au début de F01, et non une simple divergence de nommage.
9. **Feature flags** : la spec suppose Flipper (« par exemple »). Une simple colonne jsonb `entities.features` couvrirait le besoin sans nouvelle dépendance (règle du dépôt : pas de dépendance spéculative).
10. **Hypothèse « l'intégration Digiteal et le JWT existent »** : Digiteal existe mais n'est pas validé (écrit de mémoire). Le JWT existe mais est déprécié au profit des clés `lf_…`. Le fournisseur d'AP retenu est B2Brouter.
11. **Langues fr, nl, en** vs règle projet « UI en anglais » (`MEMORY.md`). Le coût d'un `nl` complet et de `i18n-tasks` est élevé et n'a pas été arbitré. **Question pour l'utilisateur.**
12. **Exigences de test très lourdes** (Mutant ≥ 85 %, couverture ≥ 95 % *par dossier* `app/features/<nom>/`, séquences aléatoires, 500 000 lignes). L'arborescence `app/features/<nom>/` n'existe pas : le code est organisé par type (`app/services/accounting/…`). Imposer `app/features/` obligerait à créer une seconde convention à côté de la première.
13. **Règle de CLAUDE.md « Ne jamais modifier BudgetFlow ni l'intégration Digiteal »** : la spec §17.1 propose d'ajouter ces règles. Je n'ai pas touché `CLAUDE.md`.
14. **Conservation des pièces et RGPD** : `retention_until` de 10 ans « à confirmer avec la réglementation ». À valider par un comptable avant de coder, avec inscription dans `docs/dev/features/QUESTIONS.md` (fichier à créer).
15. **F06 « écarts d'arrondi 0,01 € par catégorie »** et les règles de score F02/F04 sont des décisions fonctionnelles chiffrées. Elles devront être reprises telles quelles, sans ajustement par l'agent.

## 6. Plan détaillé de la vague P0, tâche par tâche

Principes : TDD strict, un commit par étape cohérente, **aucun commit sans demande**. Les noms ci-dessous sont les noms réels du dépôt. Chaque étape se termine par la suite complète verte (~2 min 30, en arrière-plan) et `bin/rubocop` sur les fichiers touchés.

### Préliminaires (sans code)

0.1. **Décisions** à valider avant d'écrire du code (§7) : drapeaux, `app/features/`, langues, convention de taux, CODA, échantillons.
0.2. Créer `docs/dev/features/QUESTIONS.md`.

### F01 — Droits et verrouillage (4 à 6 sessions)

1. **Specs de caractérisation de l'existant** (policies actuelles, comportement des rôles) pour ne rien casser en changeant le modèle de droits.
2. **`Permissions::MATRIX`** (rôle × permission) et traduction des 5 rôles actuels (`admin/accountant/manager/auditor/budget_user`) vers les 5 rôles de la spec ; test qui parcourt toute la matrice, interface et API.
3. **Migration réversible** `roles`/`permissions` (ou matrice en code + `memberships` étendus : `valid_from`, `valid_until`, `journal_ids`) ; `entities.four_eyes`, `four_eyes_threshold` ; `journal_entries.created_by_id`, `posted_by_id`.
4. **Policies par permission, scope société** : remplacer les contrôles par rôle global ; exemple partagé `company scoped` (renommer ou compléter `entity scoped report`) appliqué à chaque endpoint.
5. **`period_locks`** (migration + modèle + service verrouiller/déverrouiller avec motif, notification) ; reprise du verrou TVA de `VatDeclaration`.
6. **`Ledger::PostEntry`** (façade : garde de période, statut d'exercice, quatre yeux, `created_by`) branchée sur `PostJournalEntry` ; spec de bord de période (premier et dernier jour).
7. **Trigger PostgreSQL** de verrouillage (INSERT/UPDATE/DELETE sur lignes validées d'une période verrouillée) avec variable de session pour la fenêtre contrôlée ; spec en SQL brut ; spec d'invariants I1 à I11 après.
8. **TOTP** pour les rôles sensibles, garde-fous (dernier propriétaire), expiration d'accès auditeur, filigrane PDF.
9. **Écrans** : Utilisateurs et rôles, Périodes (frise), bandeau de période verrouillée. API : jetons bornés par les droits.
10. **Audit** : connexions et échecs, changements de droits, verrouillages. Drapeau `feature_f01`. `docs/dev/features/F01.md`.

### F03 — Documents (4 à 6 sessions)

1. Extensions `unaccent`, `pg_trgm` (migration réversible, utile aussi à F02).
2. `documents` et `document_links`, modèles, policies ; **noyau uniquement** : dépôt, doublon par SHA-256, lien signé avec scope société, rattachement à une écriture.
3. Reprise des `ubl_document`/`pdf_document` de `Invoice` comme liens (sans déplacer de fichier).
4. Contrôle MIME réel, taille, XML sans entités externes, ZIP piégé.
5. Boîte de réception, glisser-déposer, visionneuse (drill-down R02 « pièce en trois clics »).
6. Extraction (couche texte PDF, UBL, puis OCR), propositions, brouillon prérempli via `Ledger::PostEntry`.
7. Recherche plein texte, découpe PDF, `documents:verify`, rétention, `legal_hold`, ActionMailbox.
8. Audit, drapeau `feature_f03`, `F03.md`.

### F02 — CODA et rapprochement (6+ sessions)

1. **Échantillons CODA anonymisés** (prérequis fourni par l'utilisateur).
2. Étendre `accounting_bank_transactions` (ou `bank_statements`/`bank_statement_lines` si la décision va dans ce sens) : empreinte de ligne, contrepartie, IBAN, communication, soldes de relevé.
3. `Banking::StatementParser` (interface) ; adapter les parseurs CAMT et CSV existants ; **nouveau** `Banking::Coda::Parser`.
4. `import_batches` : atomicité, empreinte du fichier, recoupement de relevés, chaînage des soldes.
5. Moteur de score : règles 1 à 6 dans `MatchBankTransaction` (réutiliser `StructuredCommunication`), sans le réécrire. Tests de non-régression sur un jeu étiqueté de 200 lignes.
6. `bank_rules`, paiement groupé, partiel, virement interne.
7. Écran à deux volets ; extourne du paiement au défaisage ; permissions `bank.import`, `bank.match` ; audit ; `feature_f02`.
8. Invariant I5 et écart de R06 nul après import.

### Fin de vague

Revue §17.5, critères de sortie P0 du §3 de la spec, parcours système CODA → rapprochement → période verrouillée → pièce consultable.

## 7. Questions à valider avant de commencer P0

1. **Ordre** : commencer par la façade `Ledger::PostEntry` + matrice de permissions (recommandé) ?
2. **Arborescence** : respecter `app/features/<nom>/` (spec) ou rester dans `app/services/accounting/…` (existant) ?
3. **Convention de taux de change** : garder « EUR pour 1 unité » (code actuel) ?
4. **Langues** : l'interface reste en anglais, ou fr et nl sont-ils réellement attendus ?
5. **Drapeaux** : colonne jsonb sur `entities` plutôt que Flipper ?
6. **Droits** : accord pour corriger les contrôles de rôle global (impact sur toutes les policies) ?
7. **CODA** : toujours souhaité ? Peut-on obtenir des fichiers anonymisés de deux banques ?
8. **Écritures de clôture et de change** : faut-il les passer en brouillon (spec) ou garder la validation automatique actuelle ?
9. **Tests** : maintenir l'exigence Mutant ≥ 85 % et SimpleCov ≥ 95 % par fonction, ou seulement la couverture globale actuelle (≥ 95 %) ?
10. **WinBooks (F05)** : un dossier de référence sera-t-il fourni, et quand ?

---

*Ce fichier respecte la contrainte du prompt §17.2 : aucun fichier de code n'a été modifié pour le produire. J'attends votre validation avant tout code.*

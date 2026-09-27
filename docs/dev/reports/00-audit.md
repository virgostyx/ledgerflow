# Audit — Rapports comptables (§16.2)

Réalisé à partir de `docs/dev/reports/spec.md` (lu intégralement) et d'une exploration du dépôt réel. Aucun fichier de code n'a été modifié pour produire cet audit.

**Remarque de nommage transverse** : la spec est écrite en français avec des noms hypothétiques (`companies`, `company_id`, `reconciliations`, `reconciliation_id`, `nom`, `numéro BCE`...). Le code réel est en anglais et utilise des noms différents (`entities`, `entity_id`, `accounting_letterings`, `lettering_id`, `name`...). Ce n'est pas un défaut du code — c'est attendu — mais **aucun extrait SQL ou nom de colonne de la spec ne doit être copié-collé tel quel** dans une migration ou une requête : il faut toujours traduire vers les noms réels ci-dessous.

## 1. Mapping entités attendues (§3) ↔ tables réelles

Schéma réel : `db/structure.sql` (le format de schéma actif est `:sql`, voir `config/application.rb`). `db/schema.rb` est obsolète (version antérieure, il lui manque plusieurs tables) — ne jamais s'y référer.

| Entité spec | Table réelle / modèle | Écart |
| --- | --- | --- |
| `companies` | `entities` (`app/models/entity.rb`) | Racine du multi-tenant via `acts_as_tenant :entity`, `entity_id` partout (pas `company_id`). `nom`→`name`/`legal_name`. `numéro BCE`→`vat_number` (champ unique combiné VAT/BCE, pas de champ BCE séparé). **Manque** : pas de colonne "début d'exercice (mois)" sur `entities` — le début d'exercice est porté par `accounting_fiscal_years.start_date`, par exercice, pas au niveau société. |
| `fiscal_years` | `accounting_fiscal_years` | `company_id`→`entity_id`, `début/fin`→`start_date/end_date`, `statut`→`status` enum. **Écart** : 3 états réels (`open/pre_closing/closed`) contre 2 attendus (`ouvert/clôturé`) — l'état `pre_closing` doit être mappé explicitement dans les futures requêtes. Index unique `(entity_id, year)` et partiel "un seul exercice ouvert" déjà présents. |
| `accounts` | `accounting_accounts` | `numéro PCMN`→`code`, `nom`→`label_fr/label_nl`, `classe`→`account_class`, `lettrable`→`reconcilable`, `code TVA par défaut`→`vat_code_default`. **Écart notable** : le "type" attendu (général/client/fournisseur/banque/TVA) n'existe pas sur `accounts` — `account_type` réel est une classification générique (asset/liability/equity/revenue/expense). Le rôle métier client/fournisseur est porté par `accounting_partners.partner_type`, et banque par `accounting_journals.journal_type`, pas par le compte lui-même. |
| `journals` | `accounting_journals` | `nom`→`label_fr`, `compte de contrepartie`→`default_account_id`. **Écart** : `journal_type` enum réel = `{purchase, sale, bank, cash, misc, payroll}` — pas de type `OD` ni `ouverture` explicite (le journal d'ouverture attendu par le §5 pour le calcul de l'ouverture des soldes n'a pas d'équivalent typé ; `misc` pourrait servir de proxy mais ce n'est pas garanti). |
| `journal_entries` | `accounting_journal_entries` | `date comptable`→`entry_date`, `référence`→`reference`. **Manques** : pas de colonne `numéro` séquentielle distincte de `reference` (bien qu'il existe `Journal#next_sequence_number` qui génère une référence du type `PREFIX2024/0001`) ; pas de `date pièce` (document date) séparée de `entry_date` ; pas de `posted_at` (seul `locked_at/locked_by`, générique) ; pas de `created_by` en colonne directe (traçable seulement via PaperTrail `versions.whodunnit` si le modèle inclut `Auditable`). `statut` réel a 3 états (`draft/posted/reversed`) contre 2 attendus. |
| `journal_entry_lines` | `accounting_journal_entry_lines` | `entry_id`→`journal_entry_id`, `libellé`→`label`, `code TVA`→`vat_code`, `reconciliation_id`→`lettering_id`, `devise/montant devise`→`currency/amount_currency`. **Manque** : pas de colonne `échéance` (due date) sur la ligne elle-même (seule `accounting_invoices.due_date` existe, non dénormalisée). **Dénormalisation partielle** : `entity_id` est bien présent et indexé sur cette table (conforme à la spec), mais **`entry_date` ne l'est pas** — toute requête filtrant par date doit encore joindre `accounting_journal_entries`. |
| `partners` | `accounting_partners` | `nom`→`name`, `type`→`partner_type` enum `{customer, supplier, both}` (correspond bien à client/fournisseur/les deux), `n° TVA`→`vat_number`, `pays`→`country`. **Manque** : pas de flag `assujetti` — le statut TVA n'est déductible qu'indirectement (présence/format du `vat_number`, helpers `eu_country?`/`domestic?`). |
| `reconciliations` (lettrage) | `accounting_letterings` | `matched_at`→`lettered_on` (date, pas datetime). **Manque** : pas de `matched_by` (acteur) sur la ligne de lettrage elle-même — le modèle `Lettering` n'inclut pas le concern `Auditable`. Complément : `accounting_line_allocations` gère les rapprochements partiels, avec la même lacune sur l'acteur. |
| `bank_statements`/`bank_statement_lines` | `accounting_bank_accounts` + `accounting_bank_transactions` | **Écart structurel** : il n'existe pas de notion de "relevé" groupé — les transactions bancaires sont plates, rattachées directement au compte, sans solde d'ouverture/clôture par relevé (seul `bank_accounts.balance` est un solde courant unique). Le lien vers l'écriture est `journal_entry_id` (toute l'écriture), pas `journal_entry_line_id` (une ligne précise) comme attendu par le §3. |
| `attachments` | **absent** | ActiveStorage est présent au `Gemfile.lock` mais **non câblé** : aucune table `active_storage_*` dans `db/structure.sql`, aucun `has_one_attached`/`has_many_attached` dans `app/models`. Aucune table `attachments` custom non plus. Le drill-down "pièce justificative" (R02, R06...) n'a **aucune fondation existante**. |
| `audit_logs` | `accounting_audit_logs` | `acteur`→`user_id`+`user_email`, `objet (type,id)`→`auditable_type/auditable_id`, `IP`→`ip_address`, `horodatage`→`created_at`. **Écart** : un seul champ `payload` (jsonb) porte l'état, pas de paire distincte `avant`/`après` — à structurer par convention applicative, le schéma ne l'impose pas. **Point à signaler** : un second mécanisme d'audit coexiste déjà via PaperTrail (table `versions`, concern `Accounting::Auditable` utilisé par exemple sur `journal_entry.rb`, `account.rb`) — deux systèmes d'audit parallèles avec des périmètres qui se recoupent partiellement, à clarifier avant R18. |

**Vue `posted_lines`** : **absente**. Aucune gem `scenic`, aucun `CREATE VIEW` dans `db/structure.sql`, aucun fichier sous `db/views/`. À créer au socle P0, en mappant les vrais noms de colonnes (`accounting_journal_entry_lines` ⋈ `accounting_journal_entries`, filtré sur `status = posted`).

**Index requis par le §3** — état réel :

| Index attendu | État |
| --- | --- |
| `(account_id, entry_date, id)` sur journal_entry_lines | Absent (entry_date n'est même pas sur cette table ; seul un index simple sur `account_id` existe) |
| `(partner_id, account_id) WHERE reconciliation_id IS NULL` | Absent (seul un index simple sur `partner_id` existe) |
| index sur `reconciliation_id` | Présent, mais sous le nom réel `index_accounting_journal_entry_lines_on_lettering_id` |
| `(company_id, fiscal_year_id, entry_date) WHERE status='posted'` sur journal_entries | Absent (index simples séparés sur `entity_id`, `entry_date`, `fiscal_year_id`, `status`, mais pas de composite ni de partiel) |
| `(journal_id, fiscal_year_id, number)` | Absent — et **`number` n'existe pas** comme colonne (seul `reference`, avec un index unique partiel `(entity_id, reference) WHERE reference IS NOT NULL`) |
| `audit_logs (object_type, object_id, created_at)` | Partiel — le composite `(auditable_type, auditable_id)` existe, mais sans `created_at` ; `created_at` est indexé seul ou avec `entity_id`, jamais avec le couple type/id |

Tous ces index sont donc à créer au socle P0, en migrations réversibles.

## 2. Migrations nécessaires par vague, avec risque

- **P0** : vue `posted_lines` ; les 6 index composites/partiels ci-dessus ; `amount_residual` + table `reconciliation_items` (§7) ; `bank_reconciliation_reports` (§8) ; câblage ActiveStorage ou table `attachments` dédiée ; colonnes manquantes sur `accounting_journal_entries` (`document_date`, `posted_at`, `created_by_id`) et sur `accounting_journal_entry_lines` (`due_date`, `entry_date` dénormalisé).
  **Risque principal** : dénormaliser `entry_date` sur `journal_entry_lines` demande un callback de maintenance + un backfill sur une table potentiellement volumineuse en production — migration réversible mais coûteuse à exécuter (à faire par batch, hors heures de pointe).
- **P1** : `report_templates/report_lines/report_line_accounts` (rubriques bilan/résultat) — net nouveau, faible risque. `vat_codes/vat_grid_mappings/vat_transactions/vat_periods` — **risque élevé** : un système TVA fonctionnel existe déjà sous une forme différente (`Accounting::VatDeclaration`, `VatGridQuery`, logique portée par les lignes de facture, listing intracom, export XML Intervat). Créer les tables normalisées de la spec en parallèle créerait deux sources de vérité TVA à réconcilier — **décision à prendre avec l'utilisateur avant de coder R09/R10** : migrer l'existant vers le modèle de la spec, ou adapter la spec au modèle existant. `budgets/budget_lines/budget_line_periods/budget_syncs/budget_line_comments` + `exchange_rates` — net nouveau, faible risque en soi, mais bloqué par le point §4 ci-dessous.
- **P2** : `analytic_axes/analytic_accounts/analytic_lines` — l'existant a déjà `AnalyticByAxisQuery`/`AnalyticCrossQuery`/`AnalyticProjectQuery` fonctionnels ; vérifier le chevauchement avant de créer un modèle analytique parallèle. `kpi_snapshots`, `recurring_cash_items`, `cash_forecast_items`, colonnes `cash_flow_category`/`fixed_cost` sur `accounts` — net nouveau, faible risque.
- **P3** : `fixed_assets/depreciation_lines`, `accruals`, `consistency_runs/consistency_findings`, colonnes `service_start/service_end` — net nouveau, faible risque isolé, mais R18 (audit) chevauche les mécanismes d'audit déjà en place (voir §5).
- **Transverse** : `saved_reports/report_schedules/report_runs` — net nouveau, faible risque.

## 3. Services, composants et exports déjà réutilisables

- **LightService** : gem présente, convention établie et cohérente — organizer + actions sous `app/services/accounting/`, ex. `generate_vat_return.rb` (organizer) / `actions/compute_vat_grids.rb` (action), `letter_lines.rb` (organizer à 4 étapes). Les nouveaux organizers de rapports doivent suivre ce même style, pas un style `Reports::*::Service` inventé.
- **Requêtes déjà existantes, à adapter plutôt qu'à réécrire** : `TrialBalanceQuery`, `GeneralLedgerQuery`, `AgedBalanceQuery`, `StaleCreditsQuery`, `AnalyticByAxisQuery`, `AnalyticCrossQuery`, `AnalyticProjectQuery`, `IntracomListingQuery`, `VatGridQuery`, `OverdueReminders` (`app/queries/accounting/`). Elles couvrent déjà une bonne partie du calcul de R01, R02, R04, R05, R08 (partiellement, via `AnnualAccounts`), R09, R10 et R12.
- **`Accounting::ReportsController`** + `Accounting::ReportPolicy` + routes `namespace :reports` (imbriqué dans `accounting`) déjà en place pour `trial_balance`, `balance_sheet`, `income_statement`, `annual_accounts`, `general_ledger`, `aged_balance`, `analytic_by_project/axis/cross`.
- **ViewComponents réutilisables** : `Layouts::TrialBalanceComponent`, `Layouts::ReconciliationPanelComponent`, `Ui::FilterPanelComponent` (+ `filter_panel_controller.js`), `Ui::ColumnHeaderComponent`, `Accounting::BalanceIndicatorComponent`, `Accounting::MoneyDisplayComponent`. **Manque** : aucun composant "drill-down link" dédié — `Reports::DrillLinkComponent` de la spec est net nouveau.
- **Exports existants, à généraliser plutôt qu'à dupliquer** : XLSX via `caxlsx`/`caxlsx_rails` (templates `.xlsx.axlsx` dans `app/views/accounting/reports/`), CSV inline (méthodes privées `*_csv` dans `Accounting::ReportsController`, via `CSV.generate` stdlib), PDF via Prawn (`Accounting::InvoicePdf`, pas encore utilisé pour un rapport comptable). `ferrum` est au `Gemfile` mais non utilisé en dehors des tests système. **Aucune abstraction `Reports::Exporters::Csv/Xlsx/Pdf`** — à créer en factorisant le CSV inline existant, pas en réécrivant de zéro.
- **Lettrage** : déjà complet (`Accounting::Lettering`, organizer `LetterLines`, `UnletterLines`, `RemoveAllocation`) et déjà consommé par `AgedBalanceQuery`/`StaleCreditsQuery` — aucune reconstruction nécessaire pour R04/R05, seulement le mapping de nommage `reconciliation_id`→`lettering_id`.
- **Bullet** : gem présente au `Gemfile` mais **non configurée** (aucun `Bullet.enable = true` dans `config/environments/*`, aucun `config/initializers/bullet.rb`). À activer en dev/test **avant** d'écrire les nouvelles requêtes de rapports, sinon la règle "aucun N+1, tests échouent sinon" du §2.4 de la spec n'est pas vérifiable.
- **Genuinement absent** : `app/reports/` (n'existe pas du tout), budget vs réalisé (R11), registre d'immobilisations dédié (R16 — de la logique de dotation TVA existe déjà côté fixe asset review, mais pas de rapport), écran de piste d'audit (R18 — la journalisation existe, l'écran non), contrôles de cohérence automatiques (R19).

## 4. Endpoints réels BudgetFlow vs contrat §11

**Aucune intégration sortante n'existe.** Recherche exhaustive : pas de classe `BudgetFlowClient` (ni sous ce nom ni un équivalent), aucun appel HTTP sortant vers BudgetFlow dans `app/`.

Ce qui existe réellement :
- `config/initializers/budgetflow_api.rb` : `BUDGETFLOW_API_URL` et `BUDGETFLOW_JWT_SECRET` (variables d'environnement), utilisées pour **décoder** un JWT — c'est-à-dire pour l'auth **entrante** (BudgetFlow appelant LedgerFlow), via `Api::JwtService`.
- `config/routes.rb` : un commentaire marque la zone de routes API destinée à BudgetFlow (entrant), pas de client sortant.
- `docs/dev/LedgerFlow_ConceptNote_v2.md` §6.4 : un pseudocode de design (`Api::BudgetflowClient`, `httparty`, jamais implémenté) — c'est un document de conception, pas du code.

**Écart avec le contrat JSON du §11 de la spec : total.** Le contrat (`budget_id`, `version`, `funder`, `lines[]` avec `mapping.accounts`/`mapping.analytic`...) est une **hypothèse non vérifiée** contre une vraie API. Conclusion pour l'agent : avant de coder quoi que ce soit pour R11, il faut obtenir la documentation réelle des endpoints BudgetFlow (hors de ce dépôt, probablement dans le dépôt BudgetFlow lui-même) et confirmer le contrat avec l'utilisateur. Ne jamais modifier BudgetFlow — conforme à la règle déjà ajoutée à `CLAUDE.md`.

## 5. Points ambigus ou contradictoires avec le code existant

1. **Traduction obligatoire.** La spec écrit tout en français avec des noms hypothétiques ; le code réel est en anglais avec des noms différents (voir tableau §1). Tout prompt futur généré depuis la spec doit être adapté aux vrais noms — ne jamais copier un extrait SQL de la spec tel quel dans une migration ou requête.
2. **R11 bloqué** : dépend d'une API BudgetFlow sortante non implémentée ; le contrat du §11 est à confirmer avant tout code (voir §4).
3. **R09/R10 en risque de duplication** : la spec suppose un modèle TVA normalisé (`vat_codes`, `vat_periods`, `vat_transactions`) alors qu'un système TVA fonctionnel et déjà en production existe sous une forme différente (`VatDeclaration` + `VatGridQuery` + listing intracom + export Intervat XML). Construire les tables de la spec en parallèle créerait deux sources de vérité TVA. **À valider avec l'utilisateur avant la vague P1** : migrer l'existant vers le modèle normalisé de la spec, ou adapter la spec pour s'appuyer sur le modèle existant.
4. **`posted_lines` comme source unique** : tous les query objects existants interrogent directement les tables réelles, pas de vue intermédiaire. Migrer vers `posted_lines` est un changement transverse à faire une seule fois, au socle, avant tout nouveau rapport — sinon on introduit deux chemins de calcul (via la vue pour les nouveaux rapports, direct pour les anciens).
5. **Deux mécanismes d'audit coexistent déjà** (`accounting_audit_logs` + PaperTrail `versions`). Le R18 de la spec en ajoute un troisième modèle (chaîne de hash SHA-256, trigger interdisant UPDATE/DELETE côté rôle applicatif). À clarifier explicitement : R18 remplace-t-il l'un des deux, les complète-t-il, ou faut-il les unifier avant d'ajouter une troisième couche ?
6. **`fiscal_years.status` a 3 états** (`open/pre_closing/closed`) contre 2 attendus par la spec (`ouvert/clôturé`). L'état intermédiaire `pre_closing` doit être explicitement mappé (probablement traité comme "ouvert" pour les calculs de rapport, à confirmer) dans toutes les futures requêtes de rapport qui filtrent sur le statut de l'exercice.
7. **`attachments` totalement absent** alors que plusieurs rapports (R02, R06, R16, R17) supposent un drill-down vers une pièce justificative. ActiveStorage est au `Gemfile` mais non câblé — décision à prendre : câbler ActiveStorage nativement (`has_one_attached`) plutôt que créer une table `attachments` custom, sauf contrainte non identifiée qui l'empêcherait.
8. **Pas de notion de "relevé bancaire" groupé** — le §6/§8 de la spec (rapprochement bancaire, chaînage des soldes entre relevés) suppose des relevés avec solde d'ouverture/clôture propres ; le modèle réel (`accounting_bank_transactions`) est plat. Une table de regroupement (ou l'usage prévu de `bank_reconciliation_reports` au §8) devra porter cette notion.

## 6. Plan d'implémentation détaillé de la vague P0

Ordre de commits proposé, chacun testé avant de passer au suivant :

1. Activer Bullet en dev/test (`Bullet.enable = true` + config Rails logger) — prérequis pour détecter tout N+1 dès les premières requêtes de rapport.
2. Créer la vue SQL `posted_lines` (mapping des vrais noms de colonnes listés au §1) avec ses specs de requête.
3. Migrations réversibles pour les 6 index manquants du §1, et pour la dénormalisation de `entry_date` sur `accounting_journal_entry_lines` (colonne + callback de maintenance + tâche de backfill par batch).
4. `amount_residual` sur `journal_entry_lines` + table `reconciliation_items` (§7 de la spec).
5. Table `bank_reconciliation_reports` (§8), en couvrant aussi le manque de "relevé bancaire groupé" identifié au §5.8 ci-dessus.
6. Socle `Reports::Result`/`Reports::Filters`/`Reports::Period` (`Data.define` + ActiveModel), pensés pour être consommés par les query objects **existants** adaptés (pas remplacés).
7. `Reports::Exporters::Csv/Xlsx/Pdf`, en factorisant le CSV inline déjà présent dans `Accounting::ReportsController` et en réutilisant `caxlsx_rails`/Prawn plutôt que d'introduire une nouvelle gem.
8. Composants communs : `Reports::TableComponent` (en s'appuyant sur le pattern de `Layouts::TrialBalanceComponent`), `Reports::DrillLinkComponent` (nouveau), réutilisation de `Ui::FilterPanelComponent`/`Ui::ColumnHeaderComponent`.
9. Jeu de données de référence `db/seeds/reference_ledger.rb` (société fictive, deux exercices, ~3000 écritures) + générateur de volume `rake ledger:generate[200000]`.
10. Tests d'invariants I1 à I3 (`spec/invariants/`) + exemple partagé "company scoped report" — à renommer/adapter en "entity scoped report" pour coller au vocabulaire réel (`entity_id`).
11. Seulement ensuite : adapter **R01** (déjà proche de `TrialBalanceQuery`) en suivant le prompt générique du §16.4 de la spec, comme premier rapport de la vague P0.

---

**Ce fichier respecte la contrainte du prompt §16.2 : aucun fichier de code n'a été modifié pour le produire.** J'attends votre validation avant de commencer le socle (prompt §16.3) ou tout code.

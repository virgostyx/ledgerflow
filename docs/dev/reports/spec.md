# Spécification des rapports comptables – LedgerFlow

Sep 26, 2026 · @Virgo STYX

## 1. Contexte et objectifs

Ce document décrit 20 rapports comptables à implémenter dans LedgerFlow, classés en quatre vagues de priorité (P0 à P3), avec pour chacun les règles de calcul, les filtres, le drill-down, les exports, les cas limites et les critères d'acceptation.

Il est écrit pour être donné tel quel à un agent de codage (Claude Code). L'agent doit le lire en entier, puis auditer le code existant avant d'écrire la moindre ligne (voir §16).

**Hypothèses de travail** (à corriger si elles sont fausses):

- Application Ruby on Rails avec PostgreSQL, ViewComponent, Stimulus, Tailwind, LightService et RSpec, développée en TDD.
- Plan comptable PCMN belge, devise EUR, TVA belge (grilles 00 à 88), exercice comptable pouvant différer de l'année civile.
- Multi-sociétés: chaque requête est bornée à la société courante.
- Écritures, journaux, tiers, lettrage, relevés bancaires et pièces justificatives existent déjà sous une forme ou une autre. Les manques éventuels sont listés au §3.

**Gabarit de chaque rapport**: Objectif · Filtres · Colonnes · Règles de calcul · Drill-down · Exports · Cas limites · Critères d'acceptation.

**Hors périmètre**: saisie des écritures, import CODA, Peppol, clôture automatique d'exercice, dépôt Intervat ou BNB (seuls les données et fichiers de dépôt sont produits).

## 2. Principes transverses

Tous les rapports partagent le même moteur, ce qui garantit leur cohérence mutuelle. Ces règles s'appliquent à chaque rapport des sections suivantes.

### 2.1 Architecture

- `app/reports/<nom>/` : un dossier par rapport, avec `query.rb` (SQL agrégé), `service.rb` (organizer LightService: valider les filtres, exécuter la requête, construire le résultat) et `presenter.rb`.
- `Reports::Result` : objet immuable (`Data.define`) portant `rows`, `totals`, `filters`, `generated_at`, `currency` et `warnings`.
- `Reports::Filters` : objet ActiveModel commun (société, exercice, période, comptes, journaux, tiers, statut des écritures, période comparative), validé, sérialisable en query string et en JSON.
- `Reports::Period` : value object (début, fin, libellé, période comparative) avec les helpers `fiscal_year`, `month(n)` et `as_of(date)`.
- Composants ViewComponent: `Reports::TableComponent`, `Reports::FilterBarComponent`, `Reports::DrillLinkComponent`, `Reports::TotalsRowComponent`. Stimulus pour le tri, le dépliage de lignes et la sauvegarde des filtres.
- Exports: `Reports::Exporters::Csv`, `Xlsx` et `Pdf` consomment uniquement un `Reports::Result`, jamais la requête.
- API: `GET /api/v1/reports/:name` (JWT) renvoie le même `Result` en JSON. C'est le point d'entrée pour BudgetFlow.

### 2.2 Règles de calcul

- Montants en `numeric(15,2)` en base et `BigDecimal` en Ruby, jamais `Float`. L'arrondi n'intervient qu'à l'affichage; les totaux sont calculés en base sur les valeurs exactes.
- Débit et crédit sont deux colonnes positives. Solde = débit − crédit; un solde créditeur est négatif en interne et affiché selon la convention du rapport.
- Seules les écritures au statut `posted` comptent. Une option explicite « inclure les brouillons » existe, avec un badge visible dans l'en-tête.
- Toute agrégation se fait en SQL (`GROUP BY`, `SUM ... FILTER`, fonctions de fenêtre). Aucun `.each` Ruby sur des lignes d'écriture pour calculer un total.
- Solde d'ouverture d'un compte à la date D = report à nouveau (journal d'ouverture) + lignes antérieures à D dans l'exercice. Pour les classes 6 et 7, l'ouverture est zéro au début de l'exercice.

### 2.3 Invariants comptables

Chaque invariant devient un test automatique exécuté sur le jeu de données de référence (§15) et en production via le rapport R19.

| ID | Invariant | Vérifié par |
| --- | --- | --- |
| I1 | Σ débit = Σ crédit, globalement et pour chaque écriture | R01, R19 |
| I2 | Total des soldes de la balance générale = 0 | R01 |
| I3 | Total du grand livre d'un compte = ligne du même compte dans la balance | R01, R02 |
| I4 | Solde du compte 400 = total de la balance âgée clients; compte 440 = balance âgée fournisseurs | R04 |
| I5 | Solde comptable du compte 55x = solde du relevé ± opérations en suspens | R06 |
| I6 | Résultat du compte de résultat = actif − passif du bilan, avant affectation | R07, R08 |
| I7 | Grilles TVA de la période = soldes des comptes 411 et 451, écarts expliqués | R09 |
| I8 | Total analytique (ventilé + non ventilé) = total du compte de résultat | R08, R12 |
| I9 | Total des flux de trésorerie = variation de trésorerie des comptes 55 et 57 | R15 |
| I10 | Registre des immobilisations = comptes 21 à 28, amortissements et dotation de l'exercice | R16 |
| I11 | Régularisations par type = comptes 490 à 493 | R17 |

### 2.4 Performance et sécurité

- Budgets sur 200 000 lignes d'écriture: balance < 1 s, page de 100 lignes du grand livre < 300 ms, bilan < 1,5 s.
- Pagination par curseur (keyset) pour le grand livre. Jamais d'`OFFSET` sur les grandes tables.
- Cache via `Rails.cache.fetch`, avec une clé = société + rapport + filtres + `ledger_version` (horodatage de la dernière écriture validée ou modifiée). L'invalidation est automatique à chaque validation d'écriture.
- Aucun rapport sans scope société. Un spec vérifie qu'un utilisateur d'une autre société obtient zéro ligne.
- Autorisation par rapport (`can_view_report?(:trial_balance)`). Chaque export est journalisé dans la piste d'audit (R18).
- Aucun N+1: la gem Bullet est configurée pour faire échouer les tests.

### 2.5 Interface, i18n et accessibilité

- Locales fr, nl et en dans `config/locales/reports.*.yml`; formats de nombres et de dates selon la locale.
- En-tête de chaque rapport: société, titre, période, filtres actifs, date et heure de génération, statut des écritures incluses.
- Tableaux avec en-têtes collants, tri côté client, totaux en pied, nombres alignés à droite en chiffres tabulaires, CSS d'impression A4 paysage.
- Navigation clavier et attributs ARIA sur les tableaux et les lignes dépliables.

## 3. Modèle de données requis

Les rapports reposent sur onze entités. L'agent commence par comparer ce tableau au `db/schema.rb` existant, produit un mapping (nom attendu → nom réel) et ne crée que les colonnes ou tables manquantes, via des migrations réversibles.

| Entité | Colonnes minimales | Remarques |
| --- | --- | --- |
| `companies` | id, nom, numéro BCE, début d'exercice (mois) | Racine de tout scope |
| `fiscal_years` | company\_id, début, fin, statut (ouvert, clôturé) | Un seul exercice ouvert pour les écritures normales |
| `accounts` | company\_id, numéro PCMN, nom, classe, type (général, client, fournisseur, banque, TVA), lettrable, code TVA par défaut | Classe = premier chiffre; type pilote les rapports R04 à R06 |
| `journals` | company\_id, code, nom, type (achat, vente, banque, caisse, OD, ouverture), compte de contrepartie | Journal `ouverture` = à-nouveaux |
| `journal_entries` | company\_id, journal\_id, fiscal\_year\_id, numéro, date comptable, date pièce, référence, statut (draft, posted), posted\_at, created\_by | Numérotation continue par journal et exercice |
| `journal_entry_lines` | entry\_id, account\_id, partner\_id, débit, crédit, libellé, échéance, code TVA, reconciliation\_id, devise, montant devise | Ligne = unité de tout calcul. Contrainte CHECK: débit ≥ 0, crédit ≥ 0, un seul des deux non nul |
| `partners` | company\_id, nom, type (client, fournisseur, les deux), n° TVA, pays, assujetti | Sert R04 et R10 |
| `reconciliations` | company\_id, compte, matched\_at, matched\_by | Lie des lignes qui se soldent (lettrage) |
| `bank_statements` et `bank_statement_lines` | compte bancaire, date, libellé, montant, solde d'ouverture et de clôture, statut de rapprochement, journal\_entry\_line\_id | Alimentés par CODA ou saisie |
| `attachments` | attachable (entrée), fichier, type | Pièce justificative du drill-down |
| `audit_logs` | company\_id, acteur, action, objet (type, id), avant, après, IP, horodatage | Table en ajout seul, sans UPDATE ni DELETE |

Tables et colonnes complémentaires, créées à leur vague (voir §4), avec leur section de référence:

- P0: colonne `amount_residual` sur `journal_entry_lines` et table `reconciliation_items` (§7); `bank_reconciliation_reports` (§8).
- P1: `report_templates`, `report_lines`, `report_line_accounts` (§9); `vat_codes`, `vat_grid_mappings`, `vat_transactions`, `vat_periods` (§10); `budgets`, `budget_lines`, `budget_line_periods`, `budget_syncs`, `budget_line_comments`, `exchange_rates` (§11).
- P2: `analytic_axes`, `analytic_accounts`, `analytic_lines`, `kpi_snapshots`, `recurring_cash_items`, `cash_forecast_items`, et les colonnes `cash_flow_category` et `fixed_cost` sur `accounts` (§12).
- P3: `fixed_assets`, `depreciation_lines`, `accruals`, `consistency_runs`, `consistency_findings`, et les colonnes `service_start` et `service_end` sur les lignes de charge (§13).
- Transverse: `saved_reports`, `report_schedules`, `report_runs` (§14).

**Index PostgreSQL obligatoires**, à vérifier avec `EXPLAIN (ANALYZE, BUFFERS)` sur le jeu de données de test:

```sql
CREATE INDEX idx_lines_account_date ON journal_entry_lines (account_id, entry_date, id);
CREATE INDEX idx_lines_partner_open ON journal_entry_lines (partner_id, account_id) WHERE reconciliation_id IS NULL;
CREATE INDEX idx_lines_reconciliation ON journal_entry_lines (reconciliation_id) WHERE reconciliation_id IS NOT NULL;
CREATE INDEX idx_entries_company_period ON journal_entries (company_id, fiscal_year_id, entry_date) WHERE status = 'posted';
CREATE INDEX idx_entries_journal_number ON journal_entries (journal_id, fiscal_year_id, number);
CREATE INDEX idx_audit_object ON audit_logs (object_type, object_id, created_at);
```

`entry_date` et `company_id` sont dénormalisés sur `journal_entry_lines`, maintenus par callback et vérifiés par un test, afin d'éviter une jointure sur les requêtes les plus fréquentes.

Une vue SQL `posted_lines` (lignes validées avec date, société, exercice et journal) sert de source unique à tous les rapports. Elle est versionnée avec `scenic` ou en migration SQL.

## 4. Feuille de route

L'implémentation suit l'ordre ci-dessous, en quatre vagues. Une vague n'est terminée que lorsque tous ses critères d'acceptation passent et que les invariants du §2.3 sont verts; l'agent ne démarre pas la vague suivante avant.

| Ordre | Réf. | Rapport | Vague | Dépend de | Effort |
| --- | --- | --- | --- | --- | --- |
| 0 | — | Socle: `Reports::*`, vue `posted_lines`, index, jeu de données de référence | P0 | — | M |
| 1 | R01 | Balance générale et de vérification | P0 | Socle | S |
| 2 | R02, R03 | Grand livre et journaux, drill-down jusqu'à la pièce | P0 | R01 | L |
| 3 | R04, R05 | Balance âgée clients et fournisseurs, écritures non lettrées | P0 | R02 | M |
| 4 | R06 | Rapprochement bancaire | P0 | R02, R05 | L |
| 5 | R07, R08 | Bilan, compte de résultat, comparatif N-1, mensualisé, situation intermédiaire | P1 | R01 | L |
| 6 | R09, R10 | Déclaration TVA, listing clients, listing intracommunautaire | P1 | R02 | XL |
| 7 | R11 | Budget vs réalisé (BudgetFlow) | P1 | R01, API BudgetFlow | L |
| 8 | R12 | Analytique, marge par projet ou client | P2 | R01 | L |
| 9 | R13 | Tableau de bord des indicateurs clés | P2 | R04, R07, R08 | M |
| 10 | R14 | Prévisionnel de trésorerie | P2 | R04 | M |
| 11 | R15 | Tableau de flux de trésorerie | P2 | R07, R08 | L |
| 12 | R16 | Immobilisations et amortissements | P3 | R02 | XL |
| 13 | R17 | Régularisations (CCA, PAR, FNP, CAP) | P3 | R02 | L |
| 14 | R18 | Piste d'audit | P3 | Socle | M |
| 15 | R19 | Contrôles de cohérence automatiques | P3 | tous les invariants | M |
| 16 | R20 | Fichiers d'audit et de dépôt (SAF-T optionnel, liasse) | P3 | R07, R08, R09 | L |

Effort relatif avec un agent de codage: S = une session, M = deux à trois, L = quatre à six, XL = plus de six.

Si l'API BudgetFlow est stable avant la fin de la vague P0, R11 peut être avancé en fin de P0: le budget vs réalisé fait partie de l'usage quotidien des structures financées par des bailleurs.

**Critères de sortie de chaque vague**

- **P0**: R01 à R06 livrés; I1 à I5 verts; export Excel et PDF fonctionnels; drill-down de la balance jusqu'à la pièce en trois clics au plus.
- **P1**: R07 à R11 livrés; I6 et I7 verts; bilan et compte de résultat identiques à un dossier WinBooks de référence, à l'euro près.
- **P2**: R12 à R15 livrés; I8 et I9 verts; les indicateurs du tableau de bord se recoupent avec R04, R07 et R08.
- **P3**: R16 à R20 livrés; I10 et I11 verts; R19 tourne chaque nuit et n'affiche aucune anomalie sur le jeu de référence.

## 5. P0 · R01 Balance générale et balance de vérification

**Objectif.** Montrer, pour chaque compte, l'ouverture, les mouvements de la période et la clôture. C'est le point de départ de tous les contrôles et la référence de cohérence des autres rapports.

### Filtres

- Exercice (défaut: exercice ouvert) et période début-fin (défaut: exercice entier).
- Classes de comptes (0 à 7, multi-sélection) et plage de comptes (de, à).
- Niveau de détail: classe, 2 chiffres, 3 chiffres, compte complet.
- Masquer les comptes sans mouvement; masquer les soldes nuls.
- Journaux, inclusion des brouillons, période comparative (précédente ou N-1).
- `mode=general` (défaut) ou `mode=verification`.

### Colonnes

- **Mode général**: Compte · Libellé · Ouverture Débit · Ouverture Crédit · Mouvements Débit · Mouvements Crédit · Clôture Débit · Clôture Crédit. Ouverture et clôture sont des soldes nets, placés en Débit s'ils sont positifs, en Crédit sinon. Les mouvements sont bruts.
- **Mode vérification**: Compte · Libellé · Total Débit cumulé · Total Crédit cumulé · Solde Débiteur · Solde Créditeur.
- Avec comparatif: une colonne de solde de clôture de la période comparée et la variation (montant et %).
- Pied de tableau: totaux par groupe de colonnes et ligne « Résultat de la période » = Σ classe 7 − Σ classe 6.

### Règles de calcul

- Ouverture d'un compte = lignes validées de l'exercice dont `entry_date < début`, à-nouveaux compris. Classes 6 et 7: ouverture nulle au premier jour de l'exercice.
- Si l'exercice n'a pas de journal d'ouverture, l'ouverture des classes 0 à 5 est recalculée sur tout l'historique et le rapport affiche l'avertissement `opening_computed`.
- Les lignes parentes (classe, 2 et 3 chiffres) sont calculées en SQL avec `GROUP BY ROLLUP (left(number,1), left(number,2), left(number,3))`. Le solde d'un parent est net(Σ débit − Σ crédit), jamais la somme des colonnes Débit ou Crédit des enfants.
- Un compte présent dans les écritures mais absent de `accounts` apparaît comme « compte inconnu » avec un avertissement.
- Un compte dont le solde est à l'inverse de son sens normal (par exemple 400 créditeur) porte une icône d'alerte, sans modifier les chiffres.

```sql
SELECT a.number, a.name,
  COALESCE(SUM(l.debit - l.credit) FILTER (WHERE l.entry_date < :from), 0) AS opening_net,
  COALESCE(SUM(l.debit)  FILTER (WHERE l.entry_date BETWEEN :from AND :to), 0) AS mv_debit,
  COALESCE(SUM(l.credit) FILTER (WHERE l.entry_date BETWEEN :from AND :to), 0) AS mv_credit
FROM accounts a
LEFT JOIN posted_lines l ON l.account_id = a.id
  AND l.fiscal_year_id = :fy AND l.entry_date <= :to
WHERE a.company_id = :company
GROUP BY a.number, a.name
ORDER BY a.number;
```

Cette requête est un point de départ. L'agent l'adapte pour l'ouverture des classes 6 et 7, le journal d'ouverture et les filtres, puis vérifie le plan avec `EXPLAIN`.

### Drill-down

- Clic sur un compte: R02 (grand livre) pour ce compte, même période et mêmes filtres.
- Clic sur un montant de mouvement Débit ou Crédit: R02 limité aux lignes débit ou crédit.
- Clic sur une ligne parente: R02 sur la plage de comptes correspondante.
- Chaque lien conserve les filtres dans l'URL, et le fil d'Ariane permet de revenir à la balance.

### Exports

- XLSX: valeurs numériques, format monétaire de la locale, totaux en vraies formules `=SUM()` avec valeur en cache, volet figé sur l'en-tête.
- CSV: UTF-8 avec BOM, séparateur `;` et virgule décimale en locale fr et nl, `,` et point en locale en.
- PDF: A4 paysage, en-tête de société et de filtres répété sur chaque page, numéros de page.

### Cas limites

- Aucune écriture sur la période: tableau vide avec message explicite, pas d'erreur.
- Période à cheval sur deux exercices: refusée avec un message qui propose de choisir un exercice.
- Plus de 5 000 comptes: pagination du rendu HTML; l'export contient tout.
- Écritures en devise étrangère: la balance est en EUR, sur le montant converti stocké dans la ligne.

### Critères d'acceptation

1. Sur le jeu de référence, Σ Débit = Σ Crédit dans chacun des trois groupes de colonnes (invariant I2).
2. Pour chaque compte, clôture = ouverture + mouvements.
3. Le total de chaque niveau de détail est identique quel que soit le niveau affiché.
4. Le solde de chaque compte égale le total du grand livre R02 du même compte (invariant I3).
5. Le mode vérification et le mode général donnent les mêmes soldes de clôture.
6. Les exports XLSX, CSV et PDF contiennent les mêmes totaux que l'écran.
7. Performance: moins d'une seconde pour 200 000 lignes d'écriture.
8. Un utilisateur d'une autre société n'obtient aucune ligne.

**Tests attendus**: spec de requête (query spec) sur fixtures, request spec avec filtres, test de propriété (écritures aléatoires équilibrées → Σ = 0), spec d'export par comparaison de totaux, spec d'isolation entre sociétés.

## 6. P0 · R02 Grand livre et R03 Journaux

**Objectif.** Permettre de retrouver n'importe quelle ligne comptable, de la balance jusqu'à la pièce justificative, en quelques clics. Le drill-down est la fonction la plus importante de ces deux rapports.

### R02 Grand livre — filtres

- Compte, liste de comptes ou plage; période; journal; tiers (ce qui donne le grand livre auxiliaire d'un client ou d'un fournisseur).
- Recherche texte sur libellé et référence; montant exact ou plage min-max; sens (débit, crédit).
- État de lettrage: tous, lettrés, non lettrés. Code TVA. Inclusion des brouillons.
- Tri: date (défaut), montant, tiers, référence.

### R02 — colonnes

Date · Journal · N° d'écriture · Référence · Libellé · Tiers · Débit · Crédit · Solde cumulé · Lettrage · Code TVA · Pièce (icône).

Chaque compte forme une section avec trois lignes fixes: **Report** (solde d'ouverture), les lignes de mouvement, puis **Total des mouvements** et **Solde de clôture**.

### R02 — règles de calcul

- Solde cumulé = solde d'ouverture + `SUM(debit - credit) OVER (PARTITION BY account_id ORDER BY entry_date, entry_id, line_id)`.
- Pagination par curseur sur `(entry_date, entry_id, line_id)` avec 100 lignes par page. Le curseur embarque le solde cumulé de fin de page pour éviter de le recalculer.
- Dès qu'un filtre restreint les lignes (texte, montant, tiers, lettrage), le solde cumulé n'a plus de sens comptable: la colonne est masquée avec une infobulle qui l'explique, et les totaux portent sur les lignes filtrées.
- Les totaux de section sont calculés en SQL sur l'ensemble des lignes filtrées, pas sur la page affichée.

### R02 — drill-down

- N° d'écriture: ouvre l'écriture complète (toutes ses lignes, journal, dates, statut, auteur, lien vers son historique dans R18).
- Icône Pièce: aperçu du PDF ou de l'image dans un panneau latéral (Stimulus), avec téléchargement.
- Tiers: grand livre auxiliaire de ce tiers (R02 filtré), avec accès à sa balance âgée (R04).
- Code de lettrage: toutes les lignes de la même réconciliation, avec leur total qui doit être nul.
- Un fil d'Ariane conserve le chemin depuis la balance (R01) et permet de revenir sans perdre les filtres.

### R03 Journaux

- **Vue détaillée**: écritures d'un journal sur une période, regroupées par écriture (n°, date, référence, total) avec leurs lignes déployables. Filtres: journal, période, plage de numéros, statut (brouillon ou validée), utilisateur.
- **Vue centralisatrice** (`view=summary`): par journal et par mois, nombre d'écritures, total débit, total crédit. Chaque cellule mène à la vue détaillée.
- Pied de tableau: Σ Débit = Σ Crédit par journal.
- Les ruptures de numérotation dans un journal sont signalées par une ligne d'alerte « numéros manquants: de X à Y ».

### Exports

- PDF du grand livre avec saut de page par compte, ligne Report et ligne de clôture en gras.
- XLSX et CSV: une ligne par ligne d'écriture, colonnes identiques à l'écran, plus l'identifiant technique de la ligne.
- Au-delà de 10 000 lignes, l'export s'exécute en tâche de fond (ActiveJob), le fichier est stocké via ActiveStorage et l'utilisateur reçoit une notification avec le lien de téléchargement.

### Cas limites

- Compte à plusieurs milliers de lignes: pagination par curseur, jamais de chargement complet en mémoire.
- Écriture sans pièce: l'icône est grisée, pas d'erreur.
- Tiers supprimé ou archivé: le nom est conservé depuis la ligne (dénormalisé) pour ne pas casser l'historique.
- Ligne lettrée avec un lettrage partiel: affichée avec le code et un indicateur « partiel ».

### Critères d'acceptation

1. Le solde de clôture de chaque compte du grand livre égale la ligne du même compte dans R01 (invariant I3).
2. Le solde cumulé de la dernière ligne égale le solde de clôture, quelle que soit la page où elle se trouve.
3. Depuis R01, on atteint la pièce justificative en trois clics au plus (compte, écriture, pièce).
4. La recherche texte et le filtre par montant ne modifient pas les totaux d'autres comptes.
5. R03: Σ Débit = Σ Crédit pour chaque journal et chaque période.
6. Une rupture de numérotation créée volontairement dans les données de test est détectée.
7. Page de 100 lignes en moins de 300 ms sur 200 000 lignes.
8. L'export de plus de 10 000 lignes passe en tâche de fond sans bloquer l'interface.

**Tests attendus**: spec de requête sur curseur (pages consécutives sans doublon ni trou), request spec de drill-down, spec du composant d'aperçu de pièce, spec de détection de rupture de numérotation.

## 7. P0 · R04 Balance âgée et R05 Écritures non lettrées

**Objectif.** Mesurer les créances clients et les dettes fournisseurs ouvertes, par tiers et par ancienneté, et repérer ce qui traîne sans être rapproché. C'est le meilleur indicateur du risque de créances douteuses et de la pression sur la trésorerie.

### R04 Balance âgée — filtres

- Type: clients (compte 400), fournisseurs (compte 440) ou les deux, chacun dans sa propre section.
- Date de référence `as_of` (défaut: aujourd'hui). Le rapport doit fonctionner rétroactivement à n'importe quelle date passée.
- Base d'ancienneté: date d'échéance (défaut) ou date de pièce.
- Tranches configurables par société. Défaut, en jours de retard: Non échu · 1–30 · 31–60 · 61–90 · 91–120 · plus de 120.
- Tiers ou sélection de tiers; seuil minimal de solde; inclusion des brouillons.

### R04 — colonnes

Tiers · N° TVA · Non échu · une colonne par tranche · Total · Dont échu · % échu · Non affecté.

La colonne **Non affecté** regroupe les paiements reçus ou émis et les notes de crédit non lettrés, qui ne sont pas compensés dans les tranches sauf si l'option `net_unallocated` est cochée.

### R04 — règles de calcul

- Une ligne est ouverte à la date `as_of` si elle est sur un compte lettrable de type client ou fournisseur et si son résiduel est non nul à cette date.
- Pour la date du jour, le résiduel vient de `journal_entry_lines.amount_residual`, maintenu par le service de lettrage. Pour une date passée, il est recalculé avec la table `reconciliation_items(line_id, reconciliation_id, amount)` en ne retenant que les lettrages antérieurs ou égaux à `as_of`. Si cette table n'existe pas, l'agent la crée au début de la vague P0.
- Jours de retard = `as_of − échéance`. Sans échéance: date de pièce + conditions de paiement du tiers, à défaut la date de pièce.
- Sens naturel: un client est en débit, un fournisseur en crédit. Les montants sont affichés positifs dans le sens naturel.
- Les lignes sans tiers sur un compte collectif forment un tiers « (Sans tiers) » signalé par une alerte.
- Le total du rapport est comparé au solde du compte collectif à `as_of` (invariant I4). Tout écart s'affiche dans un bandeau avec son montant.

### R04 — drill-down

- Clic sur une cellule de tranche: liste des lignes ouvertes de ce tiers dans cette tranche.
- Clic sur le nom du tiers: grand livre auxiliaire (R02).
- Clic sur le total général: R05 pour le compte collectif.

### R05 Écritures non lettrées et état de lettrage

- **Filtres**: comptes lettrables, tiers, période, ancienneté minimale en jours, montant, état (non lettré, partiel, lettré).
- **Colonnes**: Compte · Tiers · Date · Journal · Pièce · Référence · Échéance · Débit · Crédit · Résiduel · Ancienneté en jours · Code de lettrage.
- Regroupement par tiers avec sous-total, qui doit égaler le solde du tiers dans R04.
- Section « Groupes équilibrés non lettrés »: tiers dont les lignes ouvertes se soldent à zéro sans être lettrées. Ce sont des candidats à un lettrage immédiat.
- **Propositions de lettrage**, en lecture seule: paires de lignes d'un même tiers avec montants opposés égaux, ou même communication structurée. Le rapport ne lettre jamais lui-même; un lien mène à la fonction de lettrage existante.

### Exports

- R04: XLSX avec une feuille par type (clients, fournisseurs) et une feuille de détail des lignes; PDF de synthèse; CSV.
- R05: XLSX et CSV avec le code de lettrage, pour audit.

### Cas limites

- Lettrage partiel: seul le résiduel entre dans la tranche.
- Note de crédit datée après la facture et lettrée plus tard: la balance âgée à une date intermédiaire doit encore montrer la facture ouverte.
- Échéance vide et aucune condition de paiement: repli sur la date de pièce, avec un compteur d'avertissement.
- Tiers à la fois client et fournisseur: apparaît dans les deux sections, jamais compensé.

### Critères d'acceptation

1. Total de R04 clients = solde du compte 400 à `as_of`; total fournisseurs = solde du compte 440 (invariant I4).
2. Pour un tiers de test, R04 à J−30 montre une facture ouverte que R04 à J montre payée.
3. La somme des colonnes de tranches et de Non affecté égale la colonne Total.
4. Chaque sous-total tiers de R05 égale le total du tiers dans R04.
5. Le groupe équilibré non lettré créé dans les données de test apparaît dans R05.
6. Un lettrage partiel ne réduit que le montant résiduel de la ligne.
7. Rapport calculé en moins d'une seconde pour 5 000 tiers et 200 000 lignes.

**Tests attendus**: spec de requête avec tableau de cas (dates d'échéance, lettrages complets et partiels, notes de crédit), spec d'invariant I4, spec rétroactive à trois dates, spec de composant pour les tranches configurables.

## 8. P0 · R06 Rapprochement bancaire

**Objectif.** Démontrer, pour un compte bancaire (55x) et une date d'arrêté, que le solde comptable s'explique entièrement par le solde du relevé et par des opérations en suspens identifiées. Un écart non nul est le signal d'une erreur à corriger avant toute clôture.

### Filtres

- Compte bancaire (obligatoire) et date d'arrêté (défaut: date du dernier relevé importé).
- Seuil d'ancienneté pour les alertes (défaut: 30 jours).
- Option « figer » qui enregistre le rapprochement (voir plus bas).

### Structure du rapport

Le rapport suit l'état de rapprochement classique, dans cet ordre:

1. **B** — Solde du relevé bancaire à la date d'arrêté.
2. **BN** — Écritures comptabilisées non encore présentes sur le relevé (net = débits − crédits du compte 55x). Deux sous-listes: encaissements en transit, paiements en transit.
3. **SN** — Opérations du relevé non encore comptabilisées (net, positif = entrée d'argent).
4. **Solde comptable attendu** = B + BN − SN.
5. **A** — Solde comptable réel du compte 55x à la date.
6. **Écart** = A − (B + BN − SN). Il doit être égal à zéro.

Justification: A = M + BN et B = M + SN, où M est le montant des opérations présentes des deux côtés. D'où A − B = BN − SN.

### Règles de calcul

- BN: lignes validées du compte 55x avec `entry_date ≤ date d'arrêté`, sans lien avec une ligne de relevé datée au plus tard à la date d'arrêté.
- SN: lignes de relevé datées au plus tard à la date d'arrêté, sans lien avec une écriture existante à cette date. Le calcul est rétroactif, comme pour R04, grâce à la date de création du lien.
- Un rapprochement peut lier une ligne de relevé à plusieurs lignes d'écriture (paiement groupé) et l'inverse. La somme des montants liés doit être égale de chaque côté.
- Chaînage des relevés: le solde d'ouverture de chaque relevé égale le solde de clôture du précédent. Toute rupture apparaît en alerte, avec les numéros de relevés concernés.
- Si aucun relevé n'existe à la date d'arrêté, le dernier relevé antérieur est utilisé et un avertissement l'indique.

### Colonnes des listes BN et SN

Date · Libellé ou communication · Référence · Montant · Ancienneté en jours · Lien (écriture ou ligne de relevé).

### Alertes

- Élément en suspens plus ancien que le seuil (chèque non encaissé, virement bloqué).
- Doublon potentiel: même montant, même date et même libellé dans BN ou SN.
- Écart non nul, avec le montant et un lien vers les listes qui l'expliquent.
- Rupture du chaînage des soldes entre deux relevés.

### Drill-down

- Ligne de BN: écriture correspondante dans R02, avec sa pièce.
- Ligne de SN: détail de la ligne de relevé, avec un lien vers la fonction de comptabilisation existante.
- Solde A: grand livre R02 du compte 55x jusqu'à la date d'arrêté.

### Figer un rapprochement

L'option « figer » enregistre dans `bank_reconciliation_reports` le résultat complet en JSON, un hash SHA-256 de son contenu, l'utilisateur et l'horodatage. Le rapport figé est immuable et consultable depuis l'historique; toute modification ultérieure d'une écriture antérieure à la date d'arrêté déclenche une alerte dans R19.

### Exports

- PDF avec bloc de signature (préparé par, vérifié par, date) prêt pour l'auditeur.
- XLSX avec une feuille par liste (BN, SN) et une feuille de synthèse.

### Cas limites

- Virement entre deux comptes bancaires de la société: deux lignes de relevé, une écriture par compte via un compte de transit; le rapport ne doit pas les compter comme des écarts.
- Solde de relevé négatif (découvert): traité comme tout autre solde, avec le signe correct.
- Compte en devise: rapprochement en devise du compte, écart de change signalé séparément.
- Relevé partiellement importé (fichier CODA tronqué): avertissement si la somme des lignes ne redonne pas le solde de clôture du relevé.

### Critères d'acceptation

1. Sur un jeu de données où toutes les opérations sont rapprochées, l'écart est nul et BN et SN sont vides.
2. Avec un chèque comptabilisé mais absent du relevé, BN contient ce chèque et l'écart reste nul.
3. Avec une opération de relevé non comptabilisée, SN la contient et l'écart reste nul.
4. Un paiement groupé lié à trois factures n'apparaît ni en BN ni en SN.
5. Une rupture volontaire du chaînage des soldes est signalée.
6. À une date antérieure, le rapport reproduit exactement l'état qu'il aurait eu ce jour-là.
7. Le rapport figé est identique au bit près à sa relecture (hash inchangé).

**Tests attendus**: spec de requête sur six scénarios (tout rapproché, chèque en transit, opération non comptabilisée, paiement groupé, virement interne, découvert), spec rétroactive, spec d'immuabilité du rapport figé, request spec du drill-down.

## 9. P1 · R07 Bilan et R08 Compte de résultat

**Objectif.** Produire les états financiers à n'importe quelle date, avec comparatif, variations et vue mensuelle, sans clôturer l'exercice. Bilan et compte de résultat partagent le même mécanisme de rubriques, piloté par des données et non codé en dur.

### Moteur de rubriques

- Tables `report_templates`, `report_lines` (code, libellé, niveau, parent, ordre, signe, formule) et `report_line_accounts` (rubrique, plage de comptes PCMN de-à, signe, exclusions).
- Une rubrique est soit une **somme de plages de comptes**, soit une **formule** sur d'autres rubriques (`total_actif = actifs_immobilises + actifs_circulants`).
- Deux modèles fournis en seeds: **Schéma BNB** (abrégé et complet) et **Présentation de gestion**. Les codes de rubrique BNB des seeds sont indicatifs; l'agent les valide contre le schéma officiel en vigueur avant de les figer.
- Un compte utilisé dans les écritures mais rattaché à aucune rubrique tombe dans une rubrique technique « Non classé ». Un bandeau signale le nombre de comptes concernés et le montant, afin que le bilan reste équilibré.

### R07 Bilan — filtres et colonnes

- Date d'arrêté `as_of` (défaut: fin de l'exercice ouvert) ou exercice; modèle; niveau de détail (rubrique, sous-rubrique, compte); comparatif N-1; inclusion des brouillons; avant ou après affectation du résultat.
- Colonnes: Rubrique · Exercice N · Exercice N-1 · Variation en montant · Variation en %. Actif et passif s'affichent côte à côte à l'écran large, l'un sous l'autre sur mobile et en PDF.
- **Résultat de l'exercice**: à une date intermédiaire, il est calculé comme Σ classe 7 − Σ classe 6 sur les comptes de résultat non clôturés de l'exercice, et présenté au passif. Après écritures de clôture, on lit le compte 14 sans doubler le résultat.
- Option `reclassify_contra_balances`: reclasse à l'actif un compte de dette à solde débiteur, et au passif un compte de créance à solde créditeur. Activée par défaut pour le modèle BNB, désactivée pour la présentation de gestion.

### R08 Compte de résultat — filtres et colonnes

- Période (défaut: exercice à ce jour), modèle, niveau de détail, comparatif N-1, `view=annual`, `monthly` ou `quarterly`.
- Vue annuelle: Rubrique · Période N · Période N-1 · Variation € · Variation % · % du chiffre d'affaires.
- Vue mensualisée: 12 colonnes de mois de l'exercice, colonne Cumul, colonne Cumul N-1. Les mois sont rangés par rang dans l'exercice (mois 1 à 12), pas par mois civil, ce qui reste juste avec un exercice décalé. Un mois sans donnée affiche 0, jamais une cellule vide.
- Sous-totaux définis par le modèle: marge brute, résultat d'exploitation, résultat financier, résultat avant impôts, résultat de l'exercice. Le modèle de gestion ajoute l'EBITDA, défini dans le seed et modifiable.

### Règles de calcul

- Une rubrique d'actif ou de charge se lit en débit − crédit; une rubrique de passif ou de produit en crédit − débit. Le signe est porté par la rubrique, pas par le rapport.
- Le comparatif N-1 utilise les soldes de clôture de l'exercice précédent tels que R01 les donne.
- Exercice de durée différente (premier exercice court ou long): le rapport affiche la durée en mois de chaque colonne et un avertissement de comparabilité.
- Les variations en pourcentage sont vides (et non 0 ou infini) lorsque N-1 vaut zéro.

### Drill-down

- Rubrique: liste de ses comptes avec leur solde; clic sur un compte: R02 pour la période.
- Cellule de la vue mensualisée: R02 du compte pour ce mois précis.
- Bandeau « Non classé »: liste des comptes à rattacher, avec lien vers l'écran de mapping.

### Exports

- XLSX avec formules pour les sous-totaux et les variations, et une feuille de mapping rubrique → comptes.
- PDF paginé aux normes de présentation (titre, société, date d'arrêté, N et N-1).
- JSON structuré par code de rubrique, pour le futur dépôt (R20).

### Cas limites

- Changement de plan de comptes en cours d'exercice: le mapping est versionné par date d'effet.
- Solde de rubrique négatif: affiché tel quel, avec signe, jamais réinterprété.
- Écritures d'inventaire postérieures à la date d'arrêté: exclues, avec un compteur.
- Multi-sociétés: chaque société a son propre mapping, dérivé du modèle.

### Critères d'acceptation

1. Total de l'actif = total du passif, résultat de l'exercice inclus (invariant I6).
2. Le résultat du R08 égale la ligne « Résultat de l'exercice » du R07 pour la même date.
3. Σ des 12 mois de la vue mensualisée = colonne de la vue annuelle, rubrique par rubrique.
4. Changer le niveau de détail ne modifie aucun total.
5. N-1 du bilan = clôture de l'exercice précédent dans R01.
6. Sur un dossier de référence issu de WinBooks, chaque rubrique correspond à l'euro près.
7. Aucun compte du jeu de référence n'est resté « Non classé ».
8. Bilan calculé en moins de 1,5 s sur 200 000 lignes.

**Tests attendus**: spec de requête par rubrique et par formule, spec d'invariant I6, spec de mapping (compte non classé), spec de comparabilité d'exercices de durées différentes, snapshot des exports XLSX et PDF.

## 10. P1 · R09 Déclaration TVA et R10 Listings

**Objectif.** Calculer la déclaration périodique de TVA belge à partir de la comptabilité, prouver sa cohérence avec les comptes 411 et 451, et produire les listings annuel et intracommunautaire. C'est le rapport le plus réglementé: chaque règle doit être pilotée par des données modifiables, pas codée en dur.

**Avertissement pour l'agent.** Les numéros de grille ci-dessous sont donnés de mémoire, à titre de guide. Avant de figer le seed `vat_grid_mappings`, l'agent les valide contre le formulaire officiel en vigueur du SPF Finances et signale toute divergence dans son compte rendu.

### Modèle de données spécifique

- `vat_codes`: code interne, libellé, taux, sens (vente ou achat), nature (national, intracommunautaire, autoliquidation, exportation, importation), pourcentage de déduction.
- `vat_grid_mappings`: pour chaque code et type de document (facture ou note de crédit): grille(s) de base, grille de TVA due, grille de TVA déductible. Une note de crédit suit d'autres grilles que la facture correspondante, d'où le type de document dans la clé.
- `vat_transactions`: une ligne par ligne d'écriture concernée, remplie à la validation (`line_id`, code, base, taxe, tiers, période). C'est la source unique de R09 et R10; elle est reconstructible depuis les écritures par une tâche `rake vat:rebuild`.
- `vat_periods`: période (mois ou trimestre), statut (ouverte, déposée), date de dépôt, hash du résultat figé.

### Grilles principales

| Bloc | Grilles | Contenu |
| --- | --- | --- |
| Sortie, bases | 00, 01, 02, 03 | Régime particulier; opérations à 6 %, 12 % et 21 % |
| Sortie, autres | 44, 45, 46, 47 | Services intracommunautaires; TVA due par le cocontractant; livraisons intracommunautaires; autres opérations exemptées |
| Sortie, notes de crédit | 48, 49 | Notes de crédit émises sur les grilles 44 et 46; sur les autres opérations de sortie |
| Entrée, bases | 81, 82, 83 | Marchandises et matières; services et biens divers; biens d'investissement |
| Entrée, autres | 86, 87, 88 | Acquisitions intracommunautaires; autres opérations à TVA due par le déclarant; services intracommunautaires |
| Entrée, notes de crédit | 84, 85 | Notes de crédit reçues sur les grilles 86 et 88; sur les autres opérations d'entrée |
| TVA due | 54, 55, 56, 57 | TVA sur les grilles 01 à 03; sur 86 et 88; sur 87; à l'importation avec report de perception |
| TVA déductible | 59 | TVA déductible sur les opérations d'entrée |
| Régularisations | 61, 62, 63, 64 | En faveur de l'État (61, 63); en faveur du déclarant (62, 64) |
| Solde | 71, 72 | Solde dû à l'État; solde en faveur du déclarant |

Le solde se calcule ainsi: total des grilles 54, 55, 56, 57, 61 et 63, moins total des grilles 59, 62 et 64. Un résultat positif va en 71, négatif en 72.

### R09 — filtres et colonnes

- Période (mois ou trimestre selon le régime de la société), statut de la période, inclusion des brouillons.
- Colonnes: Grille · Libellé · Montant, avec deux blocs (bases, TVA) et un pied « Solde ».
- Un panneau « Cohérence » affiche le rapprochement avec la comptabilité: solde de 451 moins 411 en fin de période, paiements de TVA de la période, acomptes, régularisations, et l'écart résiduel qui doit être expliqué ou nul (invariant I7).

### R09 — règles de calcul

- Bases: `SUM(base)` de `vat_transactions` par grille de la période, selon `vat_grid_mappings`. TVA: `SUM(taxe)` par grille de TVA.
- Contrôle de cohérence par ligne: base × taux ≈ taxe, avec une tolérance de 0,05 € par document. Au-delà, l'anomalie est listée, sans bloquer le rapport.
- TVA partiellement déductible (par exemple 50 %): la part déductible va en grille 59, la part non déductible reste dans le compte de charge. Le pourcentage est porté par le code TVA.
- Régularisations (grilles 61 à 64): saisies par écriture d'OD avec un code TVA de régularisation. Elles apparaissent avec leur libellé dans un sous-tableau.
- Une période déposée est verrouillée: aucune nouvelle écriture datée dans cette période sans passage par une régularisation dans la période suivante. Le résultat figé (JSON et hash) est conservé.

### R09 — drill-down

Grille → liste des lignes qui la composent (date, pièce, tiers, base, taxe, code) → écriture → pièce justificative. Une ligne de la liste peut être exportée seule.

### R10 Listings

- **Listing annuel des clients assujettis**: pour chaque client belge assujetti avec un chiffre d'affaires HTVA annuel supérieur au seuil réglementaire (250 € à valider): n° de TVA, nom, montant HTVA, TVA. Contrôle du numéro au format `BE0` + 9 chiffres (ou BE1 suivi de 9 chiffres), avec vérification du modulo 97 (les deux derniers chiffres valent 97 moins le reste de la division par 97 des huit premiers). La validation VIES en ligne est hors périmètre.
- **Listing intracommunautaire**: par client de l'Union, pays, n° de TVA, nature (L livraison de biens, T opération triangulaire, S prestation de services) et montant. Périodicité mensuelle ou trimestrielle selon le régime.
- Anomalies signalées: client sans n° de TVA, n° de TVA au format invalide, montant du listing différent des grilles correspondantes de R09.

### Exports

- XLSX et PDF de la déclaration avec le détail par grille, CSV des listings.
- Le fichier XML Intervat est une seconde phase, à produire à partir du schéma publié par le SPF Finances (R20). La première livraison de R09 et R10 s'arrête aux données et à leur cohérence.

### Cas limites

- Autoliquidation et opérations avec report de perception: la même écriture alimente une grille de sortie et une grille d'entrée.
- Note de crédit d'une période antérieure déjà déposée: régularisation dans la période courante.
- Crédit de TVA reporté d'une période à l'autre: affiché en report, sans double comptage.
- Ligne avec code TVA mais sans ligne de TVA correspondante, ou l'inverse: anomalie de classe « TVA orpheline ».

### Critères d'acceptation

1. Sur le jeu de référence, chaque grille de R09 égale la valeur de la déclaration déposée pour la même période.
2. Le panneau de cohérence explique l'écart avec 451 moins 411 jusqu'à zéro (invariant I7).
3. Une note de crédit alimente les grilles de notes de crédit et non les grilles de facture.
4. Un code à 50 % de déduction sépare correctement la TVA déductible de la part en charge.
5. Une période déposée refuse une nouvelle écriture et propose la régularisation.
6. `rake vat:rebuild` régénère `vat_transactions` à l'identique (test de comparaison).
7. Le listing annuel exclut les clients sous le seuil et signale les n° de TVA invalides.

**Tests attendus**: spec de mapping par code et type de document, spec de la règle du modulo 97, spec de verrouillage de période, spec d'invariant I7, jeu de données de référence avec au moins une opération de chaque nature (nationale, intracommunautaire, autoliquidation, exportation, note de crédit).

## 11. P1 · R11 Budget vs réalisé (lien BudgetFlow)

**Objectif.** Comparer le budget et le réalisé par ligne budgétaire, avec taux d'exécution et solde disponible, par projet, centre de coûts ou bailleur, et produire le rapport financier attendu par un bailleur. C'est le rapport de pilotage quotidien des structures financées par des subventions.

### Source du budget: BudgetFlow

- LedgerFlow lit le budget dans BudgetFlow via l'API REST JWT existante. Il ne l'écrit jamais.
- La synchronisation copie le budget dans `budgets`, `budget_lines` et `budget_line_periods` (montant par mois). Elle est journalisée (`budget_syncs`: date, version, nombre de lignes, statut).
- Si BudgetFlow est injoignable, le rapport utilise la dernière synchronisation et affiche sa date dans un bandeau. Il ne plante pas.
- L'agent audite d'abord les endpoints réels de BudgetFlow et adapte le contrat ci-dessous à la réalité; il ne modifie BudgetFlow qu'après accord explicite.

Contrat de données attendu, à titre de référence:

```json
{
  "budget_id": "B-2026-01",
  "version": "revised-2",
  "currency": "EUR",
  "funder": { "code": "EU", "contract": "C-123", "start": "2025-01-01", "end": "2027-12-31" },
  "lines": [
    {
      "code": "1.1", "label": "Salaires", "parent_code": "1",
      "eligible": true, "total": 120000.00,
      "periods": [{ "month": "2026-01", "amount": 10000.00 }],
      "mapping": { "accounts": ["620000-620999"], "analytic": ["PRJ-A"] }
    }
  ]
}
```

### Filtres

- Budget et version (initiale, révisée), période (mois, à date, cumulé depuis le début du contrat).
- Regroupement: ligne budgétaire, catégorie (parent), projet, bailleur.
- Devise d'affichage et table de taux de change (`exchange_rates`: paire, mois, taux, source) — taux mensuel paramétrable, par exemple celui publié par la Commission européenne.
- Seuils d'alerte de taux d'exécution (défauts: sous 70 % ou au-dessus de 100 %) et de flexibilité entre lignes (`line_flexibility_pct`, paramétrable par contrat).

### Colonnes

Ligne budgétaire · Budget total · Budget de la période · Réalisé de la période · Réalisé cumulé · Écart (budget − réalisé) · Taux d'exécution en % · Solde disponible · Commentaire libre.

Lignes de pied: total direct éligible, coûts indirects au taux forfaitaire du contrat (paramètre, applicable aux seuls coûts directs éligibles), total général. Une ligne **Réalisé non affecté** regroupe les charges qui ne correspondent à aucune ligne budgétaire, pour que le total réalisé reste égal aux charges du compte de résultat (R08).

### Règles de calcul

- Réalisé d'une ligne = Σ(débit − crédit) des lignes d'écriture dont le compte et l'éventuel code analytique correspondent à `mapping`, dans la période et dans les dates du contrat.
- Une même ligne d'écriture ne peut alimenter qu'une seule ligne budgétaire. Si deux mappings se recouvrent, l'agent le refuse à la synchronisation avec un message précis.
- Conversion: chaque ligne est convertie au taux du mois de son écriture, puis sommée. Jamais de conversion du total.
- Taux d'exécution = réalisé cumulé ÷ budget total; vide, et non infini, si le budget est nul.
- Consommation mensuelle moyenne = réalisé cumulé ÷ mois écoulés; « mois de solde » = solde disponible ÷ consommation moyenne. Ces deux indicateurs aident à repérer les lignes qui vont dépasser.
- Le commentaire libre par ligne et par période est sauvegardé (`budget_line_comments`) et reprend automatiquement dans les exports.

### Rapport bailleur

Un second mode d'affichage, `view=funder`, présente pour chaque ligne: Budget approuvé · Dépenses cumulées à la période précédente · Dépenses de la période · Dépenses cumulées · Solde · %. L'export XLSX suit ce gabarit. Il signale les lignes dont l'écart cumulé dépasse `line_flexibility_pct`.

### Drill-down

- Ligne budgétaire: comptes et codes analytiques qui la composent, avec leur réalisé.
- Cellule de réalisé: R02 filtré sur ces comptes et cette période.
- Ligne « Réalisé non affecté »: R02 des charges sans mapping, avec lien vers l'écran de mapping.

### Exports

XLSX (mode standard et mode bailleur), PDF, CSV. Les commentaires et la date de synchronisation figurent dans chaque export.

### Cas limites

- Budget révisé en cours d'exercice: chaque version est conservée; le rapport peut comparer la version initiale à la version révisée.
- Dépense antérieure au début du contrat ou postérieure à sa fin: exclue du réalisé éligible, listée dans un panneau « Hors période ».
- Ligne budgétaire supprimée dans BudgetFlow alors qu'elle porte du réalisé: conservée en lecture seule avec la mention « supprimée ».
- Écriture en devise locale sans taux mensuel: le rapport s'arrête sur cette ligne avec un message qui nomme le mois et la paire de devises.

### Critères d'acceptation

1. Réalisé affecté aux lignes + Réalisé non affecté = total des charges de R08 pour la même période.
2. Aucune ligne d'écriture n'est comptée deux fois.
3. Le taux d'exécution et le solde disponible sont corrects sur un jeu de données à trois lignes, dont une à budget nul.
4. Avec BudgetFlow hors ligne, le rapport s'affiche depuis la dernière synchronisation avec un bandeau daté.
5. La conversion ligne à ligne donne un total différent, et correct, de la conversion du total (test explicite).
6. L'export mode bailleur reproduit à l'euro près un rapport financier de référence fourni par l'utilisateur.
7. Les deux mappings en recouvrement sont refusés à la synchronisation.

**Tests attendus**: spec de synchronisation (stub HTTP de l'API BudgetFlow, cas hors ligne, cas de recouvrement), spec de requête sur le réalisé, spec de conversion mensuelle, spec du mode bailleur, request spec du drill-down.

## 12. P2 · R12 à R15 Analytique, tableau de bord, prévisionnel et flux de trésorerie

Ces quatre rapports réutilisent les requêtes des vagues P0 et P1. Aucun ne recalcule de son côté un chiffre déjà fourni par R01, R04, R07 ou R08: ils appellent les mêmes services, ce qui garantit la cohérence.

### R12 Analytique et marge par projet ou client

- **Modèle**: `analytic_axes` (projet, activité, centre de coûts, bailleur), `analytic_accounts` (par axe) et `analytic_lines` (`line_id`, axe, compte analytique, pourcentage, montant). Sur une ligne d'écriture des classes 6 et 7, la somme des pourcentages d'un même axe doit valoir 100 %.
- **Filtres**: axe principal, axe secondaire (filtre ou colonnes), période, comptes ou rubriques, comparatif N-1.
- **Vue pivot**: lignes = rubriques ou comptes; colonnes = comptes analytiques de l'axe choisi, ou mois. Colonne Total et colonne « Non ventilé ».
- **Marge par projet ou client**: Produits (classe 7) − Charges directes (classe 6) = Marge, avec Marge en % des produits. Les frais généraux sont répartis sur des lignes séparées et clairement libellées « répartition », selon une clé paramétrable (au prorata des produits ou des charges directes), jamais mêlés aux charges directes.
- **Règles**: le « Non ventilé » garantit que le total du rapport égale R08 (invariant I8). Un compte analytique archivé conserve ses écritures historiques.
- **Drill-down**: cellule → R02 filtré sur le compte analytique et le compte général.
- **Critères**: total du rapport = R08 pour la même période; somme des pourcentages différente de 100 % refusée à la validation; marge recalculée à la main identique sur trois projets de test.

### R13 Tableau de bord

Une page de cartes d'indicateurs, chacune avec valeur, comparaison (N-1 ou budget), courbe des 12 derniers mois, formule visible dans une infobulle et lien vers le rapport source. Graphiques ECharts via un contrôleur Stimulus.

| Indicateur | Formule | Source |
| --- | --- | --- |
| Trésorerie disponible | Σ soldes des comptes 55 et 57 | R01 |
| Chiffre d'affaires cumulé | Σ classe 70 sur l'exercice à ce jour | R08 |
| Marge brute % | (Ventes − coût des ventes) ÷ ventes | R08 |
| Charges fixes mensuelles | Moyenne mensuelle des comptes marqués « fixe » | R08 |
| Résultat cumulé | Σ classe 7 − Σ classe 6 | R08 |
| DSO (jours) | Créances clients TTC ÷ ventes TTC × jours de la période | R04, R08 |
| DPO (jours) | Dettes fournisseurs TTC ÷ achats TTC × jours de la période | R04, R08 |
| Besoin en fonds de roulement | (Stocks + créances commerciales + autres créances) − dettes commerciales | R07 |
| Encours échu clients | Total des tranches en retard | R04 |
| Couverture de trésorerie | Trésorerie ÷ charges fixes mensuelles, en mois | R01, R08 |

- Le calcul s'appuie sur une table `kpi_snapshots` (société, indicateur, mois, valeur) reconstruite à la demande et invalidée par `ledger_version`.
- Chaque indicateur porte un seuil vert, orange, rouge configurable par société.
- **Critères**: chaque valeur du tableau de bord égale celle du rapport source (test automatisé par indicateur); la carte s'affiche même si un indicateur échoue, avec un message d'erreur localisé.

### R14 Prévisionnel de trésorerie

- **Horizon**: 13 semaines (défaut) ou 6 mois, choix du scénario: base, prudent (retard moyen constaté par client augmenté de N jours) ou optimiste.
- **Solde initial**: Σ des comptes 55 et 57 à la date du jour, égal à l'état ajusté de R06.
- **Entrées**: créances clients ouvertes à leur échéance, décalées du retard moyen observé du client (optionnel), plus les éléments manuels.
- **Sorties**: dettes fournisseurs ouvertes à leur échéance, charges récurrentes (`recurring_cash_items`: paie, loyers, assurances), TVA estimée à la date légale d'exigibilité (paramétrable), plus les éléments manuels (`cash_forecast_items`).
- **Colonnes**: par semaine, solde initial · entrées · sorties · solde final. Ligne d'alerte si le solde final passe sous un seuil paramétrable.
- **Échéance déjà dépassée** et non payée: placée en semaine 1 dans le scénario de base, avec le retard moyen dans le scénario prudent.
- **Critères**: le solde initial égale R06; les entrées de la première semaine et des semaines antérieures égalent les créances échues et à échoir de R04; un élément manuel ajouté modifie les semaines concernées et elles seules.

### R15 Tableau de flux de trésorerie

- **Structure**: flux d'exploitation, d'investissement et de financement, puis variation nette de trésorerie.
- **Méthode indirecte**: résultat net + dotations aux amortissements et provisions ± variation du besoin en fonds de roulement (stocks, créances, dettes commerciales, dettes fiscales et sociales) = flux d'exploitation. Investissement = acquisitions et cessions d'immobilisations (classes 21 à 28). Financement = variation du capital et des emprunts (comptes 10, 17 et 43) et dividendes.
- **Méthode directe**: chaque mouvement d'un compte 55 ou 57 est classé selon la catégorie de flux (`accounts.cash_flow_category`) de la contrepartie de la même écriture. Quand l'écriture a plusieurs contreparties, le montant est réparti au prorata.
- **Règles**: les deux méthodes donnent la même variation de trésorerie, égale à clôture − ouverture des comptes 55 et 57 (invariant I9). Un montant sans catégorie va dans « Non classé », jamais ignoré.
- **Critères**: I9 vérifié sur le jeu de référence pour les deux méthodes; changer une catégorie de flux ne modifie pas la variation nette; l'export XLSX contient les deux méthodes en deux feuilles.

Invariants ajoutés à la liste du §2.3: **I8** (total analytique = total du compte de résultat) et **I9** (total des flux = variation de trésorerie).

**Tests attendus**: spec de requête par indicateur, spec d'invariants I8 et I9, spec de scénarios de prévisionnel sur un carnet de six factures, spec du composant graphique.

## 13. P3 · R16 à R20 Clôture, audit et contrôle

Ces rapports servent la révision et la clôture. Ils sont rangés en dernier parce qu'ils reposent sur tous les précédents, mais R18 (piste d'audit) doit exister dès la vague P0 en tant que journalisation: seul son rapport est reporté.

### R16 Immobilisations et amortissements

**Modèle.** `fixed_assets` (code, description, catégorie, compte d'immobilisation 21 à 28, compte d'amortissement, compte de dotation 630, date d'acquisition, date de mise en service, valeur d'acquisition, valeur résiduelle, méthode linéaire ou dégressive, durée, statut actif, cédé ou mis au rebut, écriture d'origine, fournisseur) et `depreciation_lines` (immobilisation, période, montant, écriture générée, nature: dotation, reprise, cession).

**Rapport principal: tableau des mouvements**, par catégorie d'immobilisation:

- A. Valeur d'acquisition: début d'exercice · acquisitions · cessions et désaffectations · transferts · fin d'exercice.
- B. Amortissements et réductions de valeur: début · actés · repris ou annulés suite à cession · fin.
- C. Valeur comptable nette = A − B.

**Vues complémentaires**: registre des immobilisations (une ligne par bien, avec son historique) et plan d'amortissement prévisionnel par bien et par exercice.

**Règles de calcul**

- Dotation linéaire = (valeur d'acquisition − valeur résiduelle) ÷ durée, au prorata temporis à partir du mois de mise en service. Le mode de prorata (mois complet ou jours) est un paramètre de société.
- Dotation dégressive = valeur nette comptable de début × taux, avec les limites de taux fixées par la loi et paramétrées en table, sans valeur codée en dur.
- Cession: plus ou moins-value = prix de cession − valeur comptable nette à la date de cession. Le rapport la calcule et la présente, il ne la comptabilise pas.
- Le rapport ne crée aucune écriture. Une action séparée « générer les dotations de la période » crée une écriture d'OD au statut brouillon par catégorie, que l'utilisateur valide.
- Contrôles (invariant **I10**): Σ valeurs d'acquisition par catégorie = solde des comptes 21 à 28; Σ amortissements = solde des comptes d'amortissement; dotation de l'exercice = solde du compte 630 de l'exercice.

**Drill-down**: catégorie → biens; bien → écriture d'acquisition, dotations et pièce.

**Critères d'acceptation**

1. I10 vérifié sur le jeu de référence.
2. Un bien mis en service en cours de mois est amorti selon le mode de prorata choisi, avec un test par mode.
3. Une cession partielle d'exercice donne la bonne plus ou moins-value.
4. Le plan prévisionnel amortit exactement la valeur amortissable, à un centime près sur toute la durée.
5. Les dotations générées sont en brouillon et ne changent aucun rapport tant qu'elles ne sont pas validées.

### R17 Régularisations de clôture

**Objectif.** Lister et calculer les écritures de régularisation à passer à la clôture, et contrôler que les comptes de régularisation correspondent.

**Modèle.** `accruals` (type, description, montant total, début et fin de la période couverte, compte de charge ou de produit, compte de régularisation, statut, écriture générée, écriture d'extourne).

**Types** (comptes du PCMN): charges à reporter (490), produits acquis (491), charges à imputer (492), produits à reporter (493), et factures à recevoir ou notes de crédit à établir (comptes de la classe 44 ou 41 selon le plan de la société).

**Règles de calcul**

- Charge à reporter ou produit à reporter = montant × (jours non écoulés à la date d'arrêté ÷ jours totaux de la période couverte).
- L'extourne automatique génère à l'ouverture de l'exercice suivant (ou du mois suivant, selon le paramètre) l'écriture inverse, en brouillon.
- Chaque régularisation garde un lien vers sa pièce d'origine.
- Contrôle (invariant **I11**): Σ des régularisations par type = solde des comptes 490 à 493 à la date d'arrêté.

**Aide à l'identification (cut-off)**: deux listes générées à partir des écritures.

- Factures enregistrées dans les 30 jours après la clôture dont la période de service ou la date de pièce est antérieure à la clôture: candidates à une charge à imputer ou à une facture à recevoir.
- Factures de l'exercice dont la période de service (`service_start`, `service_end`) déborde sur l'exercice suivant: candidates à un report.

**Critères d'acceptation**

1. Une assurance annuelle payée en octobre produit le bon montant à reporter au 31 décembre.
2. I11 vérifié; une régularisation sans extourne est signalée.
3. Le montant à reporter reste juste pour une année bissextile.
4. Les listes de cut-off contiennent les cas de test, et seulement eux.

**Tests attendus (R16 et R17)**: spec de calcul des dotations et des reports sur tableaux de cas, spec des invariants I10 et I11, spec des brouillons générés, spec des listes de cut-off.

### R18 Piste d'audit

**Objectif.** Répondre à la question « qui a saisi, modifié, validé ou supprimé quoi, et quand ». Sans cette traçabilité, un logiciel comptable n'est pas fiable pour un auditeur.

**Journalisation (dès le socle, vague P0).**

- Table `audit_logs` en ajout seul: un trigger PostgreSQL `BEFORE UPDATE OR DELETE` lève une exception, et le rôle applicatif n'a pas le droit d'UPDATE ni de DELETE sur la table.
- Événements: création, modification, validation, extourne et suppression d'écritures et de lignes; changements de plan comptable, de mapping, de codes TVA et de paramètres; verrouillage et déverrouillage de période; dépôt d'une déclaration TVA; lettrage et délettrage; rapprochement figé; exports; connexions et échecs de connexion.
- Chaque ligne porte l'acteur, l'action, l'objet (type et id), l'état avant et après en JSON, l'adresse IP, l'agent utilisateur, un `request_id` et un motif obligatoire pour toute action sur une écriture validée.
- Une écriture validée ne se modifie pas: la correction passe par une extourne, tracée elle aussi.
- **Chaîne d'intégrité**: chaque ligne contient `hash = SHA-256(hash précédent + contenu)`, par société. La tâche `rake audit:verify` recalcule la chaîne et nomme la première ligne rompue.

**Rapport.** Filtres: période, utilisateur, type d'action, type d'objet, numéro d'écriture, recherche texte, motif. Colonnes: horodatage · utilisateur · action · objet (lien) · résumé des changements · IP · `request_id`. Le détail ouvre un visualiseur de différences champ par champ, avant et après. L'en-tête du rapport affiche l'état de la chaîne: « intègre sur N entrées » ou « rompue à l'entrée #id ».

**Conservation.** Durée paramétrable par société. Le défaut est de 10 ans, à confirmer avec la réglementation comptable en vigueur. Aucune purge automatique avant ce terme.

**Critères d'acceptation**

1. Une tentative d'UPDATE ou de DELETE SQL direct sur `audit_logs` échoue.
2. Modifier une ligne de la table hors application (cas de test) est détecté par `rake audit:verify`, avec l'identifiant exact.
3. La correction d'une écriture validée sans motif est refusée.
4. Toute action listée plus haut crée exactement une ligne d'audit.
5. Le visualiseur de différences reproduit à l'identique l'état avant et après.

### R19 Contrôles de cohérence automatiques

**Objectif.** Détecter avant le comptable, chaque nuit, les anomalies qu'il découvrirait sinon à la clôture.

**Fonctionnement.**

- Un contrôle = identifiant, gravité (bloquant, avertissement, information), requête, message localisé, lien de correction, et une empreinte stable par anomalie.
- Exécution nocturne (ActiveJob) et à la demande; résultats stockés dans `consistency_runs` et `consistency_findings`.
- Une anomalie peut être marquée « acquittée » avec un commentaire, l'utilisateur et la date. Elle ne réapparaît pas tant que son empreinte est identique.
- Le rapport affiche le nombre d'anomalies par gravité, leur tendance sur 30 jours, et le détail filtrable. Une notification part quand une anomalie bloquante apparaît.

**Contrôles initiaux**

| ID | Contrôle | Gravité |
| --- | --- | --- |
| C01 | Écriture déséquilibrée (Σ débit ≠ Σ crédit) | Bloquant |
| C02 | Écriture datée hors de son exercice | Bloquant |
| C03 | Rupture de numérotation dans un journal | Avertissement |
| C04 | Compte à solde inversé (400 créditeur, 440 débiteur, 55 créditeur, hors tolérance) | Avertissement |
| C05 | Doublon probable (même tiers, montant, date et référence) | Avertissement |
| C06 | Ligne sur un compte archivé ou inexistant | Bloquant |
| C07 | Groupe lettré dont le total n'est pas nul | Bloquant |
| C08 | Écriture validée modifiée sans extourne | Bloquant |
| C09 | TVA orpheline, ou base × taux incohérent | Avertissement |
| C10 | Écriture ajoutée ou modifiée dans une période TVA déposée | Bloquant |
| C11 | Invariants I1 à I11 non respectés | Bloquant |
| C12 | Écart supérieur à N mois entre date de pièce et date comptable | Information |
| C13 | Compte utilisé et non rattaché à une rubrique du bilan ou du compte de résultat | Avertissement |
| C14 | Client assujetti sans numéro de TVA valide | Avertissement |
| C15 | Mois clôturé sans rapprochement bancaire figé | Avertissement |
| C16 | Écart entre le registre des immobilisations et les comptes 21 à 28 | Bloquant |
| C17 | Régularisation sans extourne planifiée | Avertissement |

**Critères d'acceptation**

1. Chaque contrôle est couvert par un test qui crée l'anomalie, la détecte, puis la corrige et constate sa disparition.
2. Un jeu de données propre ne produit aucune anomalie.
3. L'acquittement d'une anomalie la masque, et une modification qui change l'empreinte la fait réapparaître.
4. Le calcul complet prend moins de 30 secondes pour 200 000 lignes.
5. Ajouter un contrôle se fait en créant une seule classe, sans toucher à l'orchestrateur.

### R20 Fichiers d'audit et de clôture

- **Liasse de clôture**: archive ZIP contenant, pour l'exercice, les PDF de R01, R02, R04, R07, R08, R09, R16 et R17, les rapprochements bancaires figés de R06, un manifeste `manifest.json` avec le hash SHA-256 de chaque fichier, et la date de génération.
- **Export d'audit complet**: écritures avec toutes leurs lignes, plan comptable, tiers, journaux, taux de TVA, en CSV et JSON à plat. Un profil SAF-T est optionnel et n'est développé qu'à la demande explicite.
- **Données de dépôt**: JSON par code de rubrique du bilan et du compte de résultat (R07, R08) et données de la déclaration TVA (R09). La génération des fichiers XML de dépôt à partir des schémas officiels est une phase distincte, non incluse dans cette spécification.
- **Critères**: le manifeste vérifie chaque hash; la liasse se régénère à l'identique (hors horodatage) à partir des mêmes données; les totaux des PDF égalent ceux des écrans.

**Tests attendus (R18 à R20)**: spec de trigger SQL, spec de chaîne de hachage, un test par contrôle de R19, spec de manifeste de liasse.

## 14. Exports, filtres sauvegardés et planification

Cette fonction transversale se construit avec la vague P0 et sert ensuite tous les rapports. Elle ne contient aucune logique propre à un rapport: elle consomme un `Reports::Result` et une définition de filtres.

### Exports

- **Nom de fichier**: `{société}_{rapport}_{période}_{AAAAMMJJ-HHMM}.{ext}`, sans espaces ni accents.
- **XLSX** (gem `caxlsx`): valeurs numériques typées, format monétaire de la locale, totaux en formules `=SUM()`, volet figé sur l'en-tête, largeurs de colonnes calculées, mise en page d'impression A4. Une feuille « Paramètres » liste tous les filtres et la date de génération, pour qu'un export soit reproductible.
- **PDF**: rendu HTML → PDF via Ferrum (Chrome sans interface), qui réutilise le CSS d'impression des vues. HexaPDF reste l'alternative pour un contrôle fin de la mise en page. En-tête de société et de filtres répété sur chaque page, numéros de page « x / y ».
- **CSV**: UTF-8 avec BOM, séparateur et virgule décimale selon la locale, une ligne d'en-tête, aucune ligne de total mêlée aux données.
- **Gros volumes**: au-delà de 10 000 lignes, l'export passe en tâche de fond; le fichier est stocké via ActiveStorage, téléchargeable par lien signé et authentifié pendant 7 jours, puis supprimé.
- Chaque export est tracé dans l'audit (R18): qui, quel rapport, quels filtres, quel format.

### Filtres sauvegardés

- Table `saved_reports`: société, utilisateur, clé du rapport, nom, filtres en JSON, `schema_version`, visibilité (privée ou partagée avec la société), vue par défaut.
- Les périodes acceptent des jetons relatifs, résolus à chaque exécution: `current_fiscal_year`, `previous_fiscal_year`, `current_month`, `previous_month`, `last_12_months`, `year_to_date`. Un filtre sauvegardé avec « mois précédent » donne donc toujours le bon mois.
- Le `schema_version` permet de migrer les filtres sauvegardés lorsqu'un rapport évolue. Un filtre devenu invalide s'affiche avec un avertissement et sa valeur par défaut, jamais une erreur 500.
- Interface: bouton « Enregistrer cette vue », liste déroulante des vues, indicateur de la vue active.

### Planification

- Table `report_schedules`: rapport sauvegardé, fréquence (quotidienne, hebdomadaire, mensuelle avec jour), heure et fuseau horaire de l'utilisateur, formats (PDF, XLSX), destinataires, condition d'envoi (toujours, seulement si non vide, seulement si anomalies), dernière et prochaine exécution, statut.
- Table `report_runs`: chaque exécution avec son statut, sa durée, le fichier produit et son hash. Une clé d'unicité (`schedule_id` + occurrence) empêche tout doublon lors d'une relance.
- Exécution par ActiveJob avec trois tentatives et attente croissante; à l'échec définitif, l'auteur de la planification est notifié avec la cause.
- Livraison: e-mail avec pièce jointe jusqu'à 10 Mo, sinon lien authentifié. Un paramètre de société peut interdire toute pièce jointe.
- Autorisations: la planification s'exécute avec les droits de son auteur; un destinataire n'ayant pas le droit de voir le rapport ne le reçoit pas, et l'anomalie est journalisée.
- Fuseaux horaires: l'heure d'exécution suit le fuseau de l'utilisateur (par exemple Africa/Lusaka ou Europe/Brussels), avec un test sur le passage à l'heure d'été.

### Critères d'acceptation

1. Un export XLSX ouvert dans Excel recalcule ses totaux et retrouve les mêmes valeurs qu'à l'écran.
2. Un filtre sauvegardé avec « mois précédent » donne le bon mois au 1er et au 31 de n'importe quel mois.
3. Une planification mensuelle ne s'exécute qu'une fois, même si la tâche est relancée.
4. Après trois échecs, l'auteur reçoit une notification et aucun fichier partiel n'est envoyé.
5. Un destinataire sans droit sur le rapport ne reçoit rien et l'événement est tracé.
6. Un export de 50 000 lignes ne bloque pas l'interface et est disponible par lien signé.

**Tests attendus**: spec de chaque exporteur sur un `Reports::Result` de référence, spec de résolution des jetons relatifs avec `travel_to`, spec de planification avec relance, spec de droits.

## 15. Stratégie de tests et critères d'acceptation globaux

Un rapport comptable est correct quand ses chiffres se recoupent avec ceux d'un calcul indépendant. La stratégie repose donc sur un jeu de données de référence, des résultats attendus calculés hors du code testé, et des invariants exécutés en continu.

### Jeu de données de référence

Seed déterministe `db/seeds/reference_ledger.rb` (et factories associées) pour une société fictive: deux exercices, l'un clôturé avec à-nouveaux, l'autre ouvert, environ 3 000 écritures. Un générateur `rake ledger:generate[200000]` produit le volume de test de performance.

| Scénario | Contenu obligatoire | Rapports concernés |
| --- | --- | --- |
| Ventes et achats | Factures à 21 %, 6 % et 0 %, notes de crédit, acomptes | R01, R02, R09 |
| TVA particulière | Intracommunautaire, autoliquidation, exportation, TVA à déduction partielle | R09, R10 |
| Lettrage | Lettrage complet, partiel, groupé; groupe équilibré non lettré | R04, R05 |
| Banque | 2 comptes, 12 relevés, chèque en transit, opération non comptabilisée, paiement groupé, virement interne, rupture de chaînage | R06 |
| Immobilisations | 5 biens (linéaire, dégressif), une cession, une mise en service en cours de mois | R16 |
| Régularisations | Assurance annuelle payée en octobre, facture reçue après clôture pour une prestation d'avant | R17 |
| Budget | Budget à 3 lignes dont une à montant nul, une dépense hors période, une charge non affectée | R11 |
| Analytique | 3 projets, une ligne ventilée à 50/50, une ligne non ventilée | R12 |
| Devises | Écritures en devise locale avec taux mensuels, un mois sans taux | R11 |
| Anomalies volontaires | Écriture déséquilibrée en base brute, doublon, compte inversé, trou de numérotation | R19 |

**Résultats attendus indépendants.** Pour chaque rapport, un fichier `spec/fixtures/reference_ledger/expected/<rapport>.json` contient les valeurs attendues, calculées dans un tableur ou par SQL brut écrit séparément, jamais par le code testé. Un dossier réel de WinBooks, anonymisé et fourni par l'utilisateur, sert de contrôle final pour R07, R08 et R09.

### Niveaux de tests

- **Requêtes**: chaque `Query` sur fixtures, avec les cas limites de sa section.
- **Invariants**: `spec/invariants/` exécute I1 à I11 sur le jeu de référence et sur au moins 100 registres aléatoires équilibrés (graine journalisée pour rejouer un échec).
- **Requêtes HTTP** (request specs): filtres, drill-down, autorisations, isolation entre sociétés via un exemple partagé `it_behaves_like "company scoped report"` appliqué à chaque rapport.
- **Composants**: specs ViewComponent et prévisualisations.
- **Système** (Capybara): parcours Balance → Grand livre → Écriture → Pièce; export; filtre sauvegardé; planification.
- **Exports**: relecture du XLSX avec `roo`, extraction de texte du PDF, comparaison des totaux avec l'écran.
- **Performance**: `spec/performance/`, tag `:perf`, exécutés chaque nuit sur 200 000 lignes; les budgets du §2.4 sont des assertions. Un test échoue si `EXPLAIN` d'une requête principale montre un balayage séquentiel de `journal_entry_lines`.
- **Mutation**: Mutant sur les `Query` de R01, R04, R06 et R09.
- **Qualité**: RuboCop, Brakeman et Bullet sans alerte; `i18n-tasks` sans clé manquante ni inutilisée en fr, nl et en; contrôle d'accessibilité automatisé sur les tableaux principaux.

### Définition de « terminé » pour chaque rapport

- [ ] Tous les tests du rapport passent, couverture SimpleCov d'au moins 95 % sur son dossier `app/reports/`.
- [ ] Score de mutation d'au moins 85 % sur les `Query` de R01, R04, R06 et R09.
- [ ] Les invariants concernés sont verts sur le jeu de référence et sur les registres aléatoires.
- [ ] Les budgets de performance du §2.4 sont tenus.
- [ ] Les trois exports existent et leurs totaux égalent ceux de l'écran.
- [ ] Le drill-down est testé de bout en bout, filtres conservés dans l'URL.
- [ ] L'isolation entre sociétés est testée.
- [ ] Les libellés existent en fr, nl et en.
- [ ] Les exports et les consultations sensibles sont tracés dans l'audit.
- [ ] `docs/reports/<Rxx>.md` décrit filtres, règles, exemples et limites.
- [ ] Le compte rendu de l'agent liste ses hypothèses, ses écarts avec cette spécification et les points à faire valider par un comptable.

## 16. Prompts prêts à l'emploi pour Claude Code

Enregistrez ce document dans le dépôt sous `docs/reports/SPEC.md`. Les prompts ci-dessous s'y réfèrent par leurs numéros de section. Donnez-les un par un, dans l'ordre, et validez le résultat de chacun avant de passer au suivant.

### 16.1 Règles permanentes (à ajouter à `CLAUDE.md`)

```text
Rapports comptables — règles de travail
- La source de vérité est docs/reports/SPEC.md. En cas de doute, la relire; ne pas deviner.
- TDD strict: test rouge, code minimal, test vert, refactoring. Un commit par étape cohérente.
- Un rapport à la fois. Ne pas commencer le suivant tant que la définition de « terminé » (§15) n'est pas remplie.
- Montants: numeric(15,2) en base, BigDecimal en Ruby, jamais Float.
- Toute agrégation en SQL. Aucun total calculé par une boucle Ruby sur des lignes d'écriture.
- Toutes les migrations sont réversibles. Aucune donnée existante n'est modifiée ou supprimée sans accord.
- Ne jamais modifier BudgetFlow sans accord explicite.
- Si une règle comptable ou fiscale manque ou paraît douteuse, appliquer le comportement le plus prudent, l'inscrire dans docs/reports/QUESTIONS.md avec sa justification, et continuer.
- Chaque rapport respecte les règles transverses du §2 et le gabarit du §1.
- Ne jamais supprimer ou affaiblir un test pour le faire passer.
```

### 16.2 Prompt d'audit (à donner en premier, sans coder)

```text
Lis intégralement docs/reports/SPEC.md. Ne modifie aucun fichier de code.

Audite ensuite le dépôt et produis docs/reports/00-audit.md contenant:
1. Le mapping entre les entités attendues au §3 et les tables et modèles réels (nom attendu, nom réel, colonnes manquantes, colonnes différentes).
2. La liste des migrations nécessaires, classées par vague (P0 à P3), avec le risque de chacune.
3. Les services, composants ViewComponent et exports déjà présents que les rapports peuvent réutiliser.
4. Les endpoints réels de l'API BudgetFlow et l'écart avec le contrat du §11.
5. Les points du SPEC qui te semblent ambigus, contradictoires ou incompatibles avec le code existant.
6. Un plan d'implémentation détaillé de la vague P0, tâche par tâche, avec l'ordre des commits.

Arrête-toi après avoir écrit ce fichier et attends ma validation.
```

### 16.3 Prompt du socle

```text
Implémente le socle décrit aux §2, §3 (tables de la vague P0 uniquement), §14 et la journalisation d'audit du §13 (R18, partie journalisation).

Livrables:
- Reports::Result, Reports::Filters, Reports::Period, les exporteurs Csv, Xlsx et Pdf, les composants ViewComponent communs.
- La vue SQL posted_lines et les index du §3.
- audit_logs en ajout seul avec trigger et chaîne de hachage, et rake audit:verify.
- Le jeu de données de référence du §15 (seed déterministe) et le générateur de volume.
- Les tests d'invariants I1 à I3 et l'exemple partagé « company scoped report ».

Respecte la définition de « terminé » du §15. Termine par un compte rendu court: ce qui est fait, les écarts avec le SPEC, les questions ouvertes.
```

### 16.4 Prompt générique d'un rapport

```text
Implémente le rapport Rxx décrit dans la section §N de docs/reports/SPEC.md, en suivant docs/reports/00-audit.md.

Procède en TDD dans cet ordre:
1. Les valeurs attendues indépendantes du jeu de référence pour ce rapport (§15).
2. Les specs de requête, y compris tous les cas limites de la section.
3. La Query, le service LightService et le presenter.
4. Le contrôleur, l'endpoint API, les composants et le drill-down.
5. Les trois exports.
6. Les invariants concernés, l'isolation entre sociétés et les budgets de performance.
7. Les traductions fr, nl, en et docs/reports/Rxx.md.

Vérifie chaque critère d'acceptation de la section un par un, en citant le test qui le couvre. Ne passe pas au rapport suivant. Termine par un compte rendu: critères couverts, écarts, questions pour un comptable.
```

### 16.5 Prompts par vague

**P0**

```text
Implémente dans cet ordre, en appliquant le prompt générique 16.4 à chacun: R01 (§5), puis R02 et R03 (§6), puis R04 et R05 (§7), puis R06 (§8). Après chaque rapport, arrête-toi et présente le compte rendu. À la fin de la vague, vérifie les critères de sortie de P0 du §4 et exécute tous les invariants I1 à I5.
```

**P1**

```text
Implémente R07 et R08 (§9), puis R09 et R10 (§10), puis R11 (§11). Pour R07 et R08, commence par le moteur de rubriques et ses seeds, et liste dans QUESTIONS.md chaque code de rubrique BNB que tu n'as pas pu confirmer. Pour R09 et R10, valide chaque grille contre le formulaire officiel en vigueur du SPF Finances et signale toute divergence avant de figer le seed. Pour R11, commence par un test de contrat de l'API BudgetFlow avec un stub HTTP. Vérifie les critères de sortie de P1 du §4.
```

**P2**

```text
Implémente R12, R13, R14 puis R15 (§12). Réutilise les services des rapports existants; aucun chiffre déjà fourni par R01, R04, R07 ou R08 ne doit être recalculé dans une requête séparée. Ajoute les invariants I8 et I9. Vérifie les critères de sortie de P2 du §4.
```

**P3**

```text
Implémente R16, R17, R18 (rapport), R19 puis R20 (§13). Pour R19, crée un contrôle par classe, avec un test qui crée l'anomalie, la détecte, la corrige et constate sa disparition. Ajoute les invariants I10 et I11. Vérifie les critères de sortie de P3 du §4.
```

### 16.6 Prompt de revue de fin de vague

```text
Fais une revue critique de la vague P<n>, comme le ferait un expert-comptable qui n'a pas vu le code.

1. Relis les sections du SPEC de la vague et compare-les au code livré, critère par critère.
2. Exécute la suite complète, les invariants sur les registres aléatoires et les tests de performance.
3. Cherche activement des cas où un total de l'écran diffère d'un total d'export, où un rapport contredit un autre, ou où une requête omet un filtre de société.
4. Liste tout écart, même mineur, avec le fichier, la ligne et le test qui manque.

Ne corrige rien tant que je n'ai pas validé la liste.
```

## 17. Graphiques

Un graphique n'est ajouté que lorsqu'il montre en deux secondes ce qu'un tableau cache. Il s'ajoute au rapport, sans le remplacer: chaque graphique s'appuie sur le même `Reports::Result` que le tableau et ne recalcule jamais un chiffre. Cette section se réalise après la vague qui livre le rapport concerné.

### 17.1 Composants communs

- Bibliothèque ECharts, chargée via un contrôleur Stimulus unique `chart_controller`, qui reçoit sa configuration en JSON depuis le `Result`.
- Composant ViewComponent `Reports::ChartComponent` (paramètres: type, série de données, titre, unité, seuils) et un builder par type de graphique dans `app/reports/charts/`.
- Palette et polices tirées des tokens Tailwind de l'application; couleurs de gravité (vert, orange, rouge) alignées sur les seuils de R13. Mode sombre pris en charge.
- Montants formatés selon la locale de l'utilisateur, y compris dans les infobulles et les axes.
- Chargement différé: le graphique n'est monté que lorsqu'il entre dans la fenêtre d'affichage, et le tableau reste utilisable sans JavaScript.

### 17.2 Les six graphiques

| Rapport | Graphique | Données | Lecture attendue |
| --- | --- | --- | --- |
| R14 Prévisionnel | Courbe du solde de trésorerie par semaine, avec ligne de seuil et zone d'alerte | Solde final de chaque semaine, un tracé par scénario | Repérer un creux à venir et la semaine où le seuil est franchi |
| R04 Balance âgée | Barres empilées par tranche d'ancienneté, et top 10 des tiers | Total par tranche; les dix plus gros soldes | Voir si le risque est concentré sur un tiers |
| R11 Budget vs réalisé | Barres horizontales du taux d'exécution par ligne budgétaire, colorées selon les seuils | Taux d'exécution, budget total, réalisé cumulé | Repérer une sous-consommation ou un dépassement |
| R08 Résultat mensualisé | Produits et charges par mois sur deux exercices, avec ligne du résultat | Vue mensualisée N et N-1 | Détecter saisonnalité et mois anormaux |
| R15 Flux de trésorerie | Cascade (waterfall) de la trésorerie d'ouverture à la clôture | Flux d'exploitation, d'investissement, de financement | Voir d'où vient la variation de trésorerie |
| R13 Tableau de bord | Petite courbe de 12 mois sous chaque indicateur | `kpi_snapshots` | Voir la tendance d'un indicateur d'un coup d'œil |

Aucun graphique n'est ajouté à R01, R02, R03, R09, R10 et R19: leur valeur tient à la précision et au détail.

### 17.3 Règles communes

- **Source unique**: les séries sont extraites du `Result` déjà calculé. Un test vérifie que la somme de chaque série égale le total correspondant du tableau.
- **Clic = drill-down**: cliquer sur une barre, un point ou un segment ouvre le rapport détaillé filtré sur la valeur cliquée (par exemple une tranche d'ancienneté ouvre R05 sur cette tranche).
- **Alternative accessible**: chaque graphique est accompagné d'un tableau équivalent, affichable par un bouton « Voir les données », lisible par un lecteur d'écran, avec un texte alternatif qui résume l'essentiel (par exemple « solde négatif à partir de la semaine 9 »). Le sens ne repose jamais sur la couleur seule: seuils marqués aussi par un motif ou une étiquette.
- **Données vides**: un graphique sans donnée affiche un message explicite et non un cadre vide.
- **Échelles honnêtes**: les barres commencent à zéro; une courbe peut ne pas commencer à zéro mais l'axe est alors marqué clairement. Pas de graphique en secteurs sauf pour une répartition d'un tout à cinq parts ou moins.
- **Volumes**: au-delà de 500 points par série, agrégation côté serveur.

### 17.4 Export

- **PDF**: le graphique est rendu à l'identique par Ferrum (même moteur que le reste du PDF) et placé au-dessus du tableau, avec son titre, son unité et la période.
- **XLSX**: le graphique n'est pas exporté; la feuille contient les données de la série, prêtes à être tracées dans Excel.
- **Image**: bouton « Télécharger en PNG », résolution double pour l'impression.

### 17.5 Critères d'acceptation

1. Pour chacun des six graphiques, la somme des données tracées égale le total du tableau du même rapport.
2. Un clic sur un élément du graphique conduit au rapport détaillé avec le bon filtre dans l'URL.
3. Le bouton « Voir les données » affiche un tableau identique aux données tracées.
4. Le graphique du PDF est identique à celui de l'écran (comparaison d'images avec tolérance).
5. Sans donnée, le message vide s'affiche; sans JavaScript, le tableau reste complet.
6. Chaque graphique porte un texte alternatif généré et localisé en fr, nl et en.
7. Le rendu de 12 mois et de 500 points reste fluide (moins de 200 ms pour dessiner).

**Tests attendus**: spec de chaque builder de série, spec du composant (`ChartComponent`), spec système (Capybara) du clic vers le drill-down, spec de comparaison des totaux graphique et tableau, spec d'accessibilité du tableau alternatif.

### 17.6 Prompt pour l'agent

```text
Implémente la section §17 de docs/reports/SPEC.md, une fois les rapports R04, R08, R11, R13, R14 et R15 livrés.

Commence par les composants communs du §17.1 (chart_controller, Reports::ChartComponent, palette), puis ajoute les six graphiques du §17.2 un par un, en TDD. Pour chacun: le builder de série, le test de somme égale au tableau, le drill-down au clic, le tableau alternatif accessible, l'export PDF et PNG. Ne recalcule aucun chiffre: consomme le Reports::Result existant.

Vérifie les critères du §17.5 un par un, en citant le test qui couvre chacun, puis fais un compte rendu: critères couverts, écarts, questions ouvertes.
```

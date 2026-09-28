# Questions ouvertes — Rapports comptables

Journal des règles douteuses ou manquantes rencontrées pendant l'implémentation (règle du §16.1 de `docs/dev/reports/spec.md`). Comportement le plus prudent appliqué à chaque fois ; à faire valider.

## Bullet limité aux specs `bullet_strict` (socle, 2026-09-27)

Activer `Bullet.raise = true` globalement en test fait échouer 41 specs préexistants (hors périmètre rapports : factures, lettrage, immobilisations, rappels de paiement, journaux de paramétrage) qui contiennent de vrais N+1. Les corriger un par un est un chantier séparé, sans rapport avec les rapports comptables.

**Décision appliquée** : Bullet reste actif en log seul pour toute la suite, et ne fait échouer que les specs explicitement taguées `bullet_strict: true` (voir `spec/support/bullet_strict.rb`) — appliqué pour l'instant aux specs de `app/queries/accounting/*_query.rb` et `spec/requests/accounting/reports_spec.rb`.

**À faire valider** : traiter les 41 N+1 existants dans un chantier dédié, puis retirer le tag `bullet_strict` au profit d'un `Bullet.raise = true` global.

Liste des specs actuellement en échec sous Bullet strict global (pour référence du futur chantier) : `bank_reconciliation_spec.rb`, `fixed_assets_spec.rb`, `invoices_spec.rb`, `journal_entries_spec.rb`, `opening_invoice_spec.rb`, `payment_batches_spec.rb`, `payment_reminders_spec.rb`, `recurring_invoices_spec.rb`, `settings/journals_spec.rb`, `journal_entry_workflow_spec.rb` (system), `lettering_workflow_spec.rb` (system).

## `reconciliation_items` non créée : réutilisation de `accounting_line_allocations` (socle, 2026-09-27)

Le §7 de la spec demande une table `reconciliation_items(line_id, reconciliation_id, amount)` pour recalculer `amount_residual` à une date passée. Le dépôt a déjà exactement cette information, sous une forme différente et plus riche : `accounting_line_allocations` (`debit_line_id`, `credit_line_id`, `amount`, `allocated_on`) pour les lettrages partiels, et `accounting_letterings.lettered_on` pour la date d'un lettrage total.

**Décision appliquée** : ne pas créer de table dupliquée. `amount_residual` (ajoutée sur `accounting_journal_entry_lines`) est maintenue par les services de lettrage/allocation eux-mêmes (`Accounting::JournalEntryLine.resync_amount_residual!`, appelée dans `CreateAllocations`, `CreateLettering`, `UnletterLines`, `RemoveAllocation` — ces écritures passent par `update_all`/`nullify`/`destroy_all`, qui contournent les callbacks ActiveRecord, d'où l'appel explicite à chaque endpoint plutôt qu'un callback modèle unique).

**Fait en implémentant R04 (2026-09-27)** : la reconstruction rétroactive décrite ci-dessus est faite. `AgedBalanceQuery` (et `StaleCreditsQuery`, `UnletteredLinesQuery`) filtrent maintenant `accounting_line_allocations.allocated_on <= as_of` et `accounting_letterings.lettered_on <= as_of`, via le module partagé `Accounting::OpenLineSql`. Voir `docs/dev/reports/R04.md`.

## R04/R05 livrés en v1 (2026-09-27) — voir docs/dev/reports/R04.md et R05.md

Point clé : le bug de rétroactivité de `AgedBalanceQuery` déjà repéré au socle est corrigé, et la logique de reconstruction est extraite dans `Accounting::OpenLineSql` (règle des trois occurrences : `AgedBalanceQuery` + `StaleCreditsQuery` + `UnletteredLinesQuery` partagent désormais le même code, garantissant que R04 et R05 ne peuvent pas diverger). Colonnes "Dont échu"/"% échu" ajoutées. Échéance de repli enrichie avec `partner.payment_terms_days` — **changement de comportement** sur un test préexistant (`aged_balance_query_spec.rb`, corrigé pour refléter le calcul conforme au §7, pas affaibli).

Reporté : tranches configurables par société, propositions de lettrage automatiques (R05), drill-down cellule-tranche et tiers→grand livre auxiliaire, exports pour R05, filtre "état de lettrage" sur R05.

## R06 livré en v1 (2026-09-27) — **fin de la vague P0** (R01-R06 tous livrés)

Voir `docs/dev/reports/R06.md`. Confirme un écart déjà signalé au socle : sans notion de "relevé bancaire" groupé, B est reconstruit comme la somme cumulée des transactions (pas de solde d'ouverture/clôture par relevé réel), et le chaînage entre relevés (critère #5) n'est pas implémentable en l'état. `Accounting::BankReconciliationQuery` reconstruit BN/SN à `as_of` en supposant que le lien transaction↔écriture actuel existait déjà à cette date s'il existe aujourd'hui — approximation raisonnable en l'absence d'un timestamp "lié le" sur `accounting_bank_transactions`.

## R07/R08 livrés en v1 (2026-09-27)

Le "moteur de rubriques" du §9 existait déjà — `Accounting::AnnualAccounts` + `config/annual_accounts/company_abridged.yml` — sous forme YAML plutôt que tables `report_templates`/`report_lines`/`report_line_accounts`. Décision : ne pas migrer vers des tables DB (aucun besoin d'édition à chaud du modèle constaté), étendre l'existant. Ajouté : Variation €/%, vue mensualisée (R08, réutilise `movement_debit`/`movement_credit` de `TrialBalanceQuery` construits pour R01 et `Reports::Period.month`).

**Vraie régression trouvée en testant I6** : le compte `499000` (comptes d'attente) du jeu de référence n'était rattaché à aucune rubrique du modèle BNB, cassant l'équilibre actif=passif. Corrigé en l'ajoutant à la rubrique `490/1` — voir `docs/dev/reports/R07.md`.

Reporté : deuxième modèle ("Présentation de gestion" + EBITDA), `reclassify_contra_balances`, drill-down rubrique→comptes→R02, vue trimestrielle, exports PDF/JSON.

## R09/R10 — migration TVA phase 1 : `vat_codes`/`vat_grid_mappings` (2026-09-28)

Décision utilisateur : migrer vers le modèle normalisé de la spec. En creusant `Accounting::VatGrid` (le mapping actuel), deux découvertes ont changé la portée :

1. **Le mapping actuel est déjà rigoureux** — il cite les numéros de notice officielle du SPF (ex. "notice n°149-156", "notice n°98, 252"), pas des approximations. Le PDF officiel `docs/dev/notice explicative TVA.pdf` (104 pages, SPF Finances, janvier 2014) confirme que tous les numéros de grille utilisés existent bien dans le formulaire réel. La mention "approximations internes" du handoff VAT précédent semble obsolète.
2. **Le mapping se scinde en deux dimensions indépendantes** : côté vente, le taux/la nature pilote directement la grille (migrable proprement) ; côté achat, la grille de base (81/82/83) dépend du **préfixe du compte de charge**, pas du code TVA — une dimension que `vat_grid_mappings` (code × type document → grille) ne prévoit pas nativement.

**Mise à jour 2026-09-28 (même jour) — migration complète faite.** L'utilisateur a précisé que l'application **n'est pas encore en production** et m'a laissé libre : la prudence évoquée ci-dessus (ne pas toucher le chemin d'écriture d'un système en production) ne s'applique donc plus. Réalisé :

- `accounting_vat_codes` (vente **et achat**), `accounting_vat_grid_mappings` (base / TVA due / TVA déductible / grille récapitulative des notes de crédit) et **`accounting_vat_account_grid_rules`** — la dimension « préfixe de compte » (60→81, 61/64→82, 20-27→83, notice n°149-156) que le modèle de la spec n'avait pas, ajoutée en table dédiée plutôt qu'en logique Ruby.
- `Accounting::VatGrid` ne contient plus aucune constante de mapping : il **lit ces tables à l'exécution** (instantané mis en cache par processus, invalidé par `after_commit` sur les 3 modèles ou `.reset!`). Si rien n'est seedé il lève `VatGrid::NotSeeded` — échec bruyant, plus de silence sur un déploiement frais (le risque qui avait motivé ma retenue). Restent en Ruby : `.balance` (arithmétique de la déclaration, grilles XX/YY) et `LABELS`.
- Appelants migrés : `GenerateInvoiceJournalEntry` (constantes de classe supprimées), `VatGridQuery` (grilles 84/85 et autoliquidation lues des données), `RegularizeVatProrata`, `FiscalYearsController`.
- Tests : `rails_helper` seed les données VAT une fois (`before(:suite)`) et les préserve dans la stratégie truncation. **Preuve de parité** : toute la suite TVA/factures/notes de crédit existante (~100 exemples, non modifiée) passe contre le mapping en base. Spec dédiés : édition d'un mapping visible après reset, échec bruyant si vide.
- Le spec de « cohérence » de la phase 1 est supprimé : il n'y a plus deux sources à garder synchrones.

Non fait (peut venir avec R09) : `vat_transactions` (projection reconstructible `rake vat:rebuild`) et `vat_periods` — `accounting_vat_declarations` joue déjà le rôle de période (statut, dates, grilles figées).

**Prochaine étape** : construire R09 (panneau de cohérence I7) et R10 (listing annuel avec validation modulo 97, listing intracommunautaire — déjà partiellement couvert par `IntracomListingQuery`) en s'appuyant sur `VatGridQuery`/`VatDeclaration` existants, pas sur les nouvelles tables (qui ne sont pas encore la source de vérité). Puis R11 (budget BudgetFlow, bloqué tant que le contrat API réel n'est pas confirmé).

## `Reports::Exporters::Pdf` via Prawn, pas Ferrum (socle, 2026-09-27)

Le §14 de la spec décrit le PDF comme "rendu HTML → PDF via Ferrum, qui réutilise le CSS d'impression des vues", HexaPDF en alternative. Ni l'un ni l'autre n'est câblé dans ce dépôt (Ferrum est au Gemfile mais utilisé seulement pour les tests système ; HexaPDF est absent). `Accounting::InvoicePdf` existe déjà et génère des PDF via Prawn + prawn-table.

**Décision appliquée** : `Reports::Exporters::Pdf` réutilise Prawn/prawn-table, comme `InvoicePdf`, pour un tableau générique (titre, en-tête en gras, pagination "x / y"). Pas de vue HTML à réutiliser pour un exporteur générique de toute façon — la question du rendu HTML→PDF via Ferrum ne se posera vraiment que si un rapport a besoin d'une mise en page plus riche qu'un tableau (graphiques du §17, par exemple).

**À faire valider** : si un futur rapport a besoin d'un rendu plus riche que Prawn ne permet pas facilement (mise en page complexe, graphiques intégrés au PDF), reconsidérer Ferrum à ce moment-là plutôt que maintenant.

## Jeu de données de référence (`db/seeds/reference_ledger.rb`, socle, 2026-09-27)

Portée limitée aux scénarios P0 (décision utilisateur) : ventes/achats TVA, TVA particulière, lettrage (complet/partiel/groupé/groupe non lettré), banque (2 comptes, chèque en transit, opération non comptabilisée, paiement groupé, virement interne), 3 anomalies volontaires. Les scénarios immobilisations/régularisations/budget/analytique/devises du §15 s'ajoutent avec les vagues P1-P3 correspondantes.

Écarts constatés en construisant le seed, à signaler :
- **Écriture déséquilibrée (anomalie C01) impossible à créer** : le trigger `enforce_double_entry_check` vérifie l'équilibre par écriture et ne peut pas être contourné au-delà d'une transaction (`SET CONSTRAINTS ... DEFERRED` ne dispense que jusqu'au COMMIT). Une écriture réellement déséquilibrée ne peut donc pas persister dans ce schéma — bon signe pour l'intégrité des données, mais cela rend le contrôle R19/C01 actuellement invérifiable par un vrai cas positif en base ; à re-discuter si R19 veut le tester (probablement via un test qui *tente* l'insertion et vérifie le rejet, plutôt qu'un fixture persistant).
- **TVA à déduction partielle** : modélisée au niveau de l'entité (`vat_prorata_rate`), pas par code TVA comme le prévoit le modèle normalisé du §10 (qui n'existe pas — voir plus haut). Le seed règle `vat_prorata_rate: 80` sur l'entité de référence plutôt que d'inventer un champ par ligne.
- **Pas de notion de "relevé bancaire"** (déjà signalé au §1 de l'audit) : le scénario banque du seed couvre BN/SN/paiement groupé/virement interne directement sur `accounting_bank_transactions`, mais pas de "rupture de chaînage entre relevés" (aucun concept de relevé à chaîner). À couvrir quand R06 introduira `bank_reconciliation_reports` en pratique.
- Comptes de contrepartie réels : `Accounting::GenerateInvoiceJournalEntry` utilise toujours `Accounting::AccountCodes::CUSTOMERS` (400000) et `SUPPLIERS` (440000), **pas** le `default_account` du journal configuré par `Seeders::JournalsSeeder` (qui pointe vers 400100/440100, jamais utilisés en pratique pour les factures). Le seed réutilise `Accounting::AccountCodes` directement pour rester cohérent avec le code réel.

Générateur de volume : `rake ledger:generate[N]` — insertion SQL brute (deux `INSERT ... SELECT` sur `generate_series`) plutôt que N créations ActiveRecord, pour rester exploitable à 200 000 lignes ; les écritures générées sont volontairement synthétiques (comptes 600000/440000, montant fixe), seul le volume compte pour les tests de performance du §2.4.

## Invariants I1-I3 (socle, 2026-09-27) — piège de signe sur `TrialBalanceQuery#balance`

En écrivant l'invariant I2 (« Σ soldes de la balance générale = 0 »), `Accounting::TrialBalanceQuery::Result#balance` s'est révélé **volontairement orienté sens normal du compte** (positif quand un compte débiteur est débiteur, positif *aussi* quand un compte créditeur est créditeur — pratique pour l'affichage, chaque compte montre un nombre positif dans sa colonne naturelle). Sa somme sur tous les comptes n'est **pas** nulle en général (elle vaut 2× le solde net des comptes à sens débiteur) : ce n'est pas un bug, mais un piège si on l'utilise pour vérifier I2 littéralement.

**I2 vérifié à la place sur** `Σ(total_debit − total_credit)` (sens unique, brut), qui vaut 0 par construction double-entrée (I1). C'est la vraie expression comptable de « Σ soldes débiteurs = Σ soldes créditeurs » de la balance de vérification.

**I3** compare en revanche deux valeurs déjà `balance` (grand livre vs balance) *pour le même compte* — valide, puisque les deux utilisent la même convention de signe pour ce compte précis.

À garder en tête pour R01 : toute future implémentation du mode « vérification » (§5 : Solde Débiteur / Solde Créditeur en colonnes séparées) devra dériver ces deux colonnes du **net brut**, pas de `balance`.

## R01 livré en v1 réduite (2026-09-27) — voir docs/dev/reports/R01.md

Mode général, comparatif N-1, drill-down vers le grand livre, 3 exports via le socle `Reports::*`. Explicitement reporté : niveaux de détail ROLLUP (classe/2/3 chiffres), mode vérification (écran), filtres compte/classe/journal/brouillons, avertissements « compte inconnu »/« opening_computed », pagination >5000 comptes, tests de performance §2.4, traductions fr/nl des nouvelles colonnes.

## R02/R03 livrés en v1 réduite (2026-09-27) — voir docs/dev/reports/R02.md et R03.md

R02 : ouverture/mouvements/clôture par compte, filtres tiers/journal/lettrage, drill-down tiers + écriture. R03 : vue centralisatrice (journal × mois) + détection des trous de numérotation ; la vue détaillée n'a pas été reconstruite, `Accounting::JournalEntriesController#index` la couvre déjà.

Reporté, à traiter si un vrai besoin se présente (pas de fixture pour du code qui n'existe pas) : pagination par curseur `(entry_date, entry_id, line_id)` (v1 = pas de pagination du tout sur R02, à corriger avant une vraie mise en prod avec des comptes à des milliers de lignes), recherche texte/montant/code TVA, export en tâche de fond >10 000 lignes, icône Pièce (bloqué par l'absence totale de pièces jointes dans ce dépôt), page `show` pour `Accounting::Lettering` (nécessaire pour le drill-down code de lettrage → groupe complet).

**Incohérence de format à surveiller** : `Reports::TableComponent` attend des colonnes `{key:, label:, align:, format:, link:}` (hashs) alors que `Reports::Exporters::Csv/Xlsx/Pdf` attendent des tuples `[label, key_ou_proc]`. Réconcilié pour l'instant par un adaptateur local (`ReportsController#trial_balance_export_columns`). Si un deuxième rapport a le même besoin, unifier les deux contrats plutôt que dupliquer l'adaptateur (règle des trois occurrences avant d'abstraire).

## R17 — Plan comptable: comptes de régularisation
- Le PCMN livré (`db/seeds/pcmn_commercial.json`) place « Produits acquis » sous **490200** et « Produits à reporter » sous **492200**, alors que le PCMN officiel les met en **491** et **493** (490 charges à reporter, 491 produits acquis, 492 charges à imputer, 493 produits à reporter), comme le suppose la spec. Comportement prudent : R17 suit les **libellés** du plan tel que livré (`Accounting::Accrual::ACCOUNT_CODES`), sans modifier le plan. À trancher : corriger le seed (et migrer les données existantes) ou garder ce mapping.
- La spec ne donne la formule que pour les reports; pour les charges à imputer / produits acquis, le montant = total du service × part écoulée jusqu'à l'arrêté (jours écoulés ÷ jours de la période).
- Les écritures de régularisation et d'extourne sont générées en **brouillon**; I11 ne compte que les écritures validées.

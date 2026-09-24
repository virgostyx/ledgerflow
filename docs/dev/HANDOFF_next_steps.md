# LedgerFlow — Dossier de reprise (nouvelle conversation)

Objectif de la prochaine session : combler les écarts qui séparent LedgerFlow d'un outil qu'une PME ou un indépendant belge peut utiliser seul. La liste priorisée et le contexte technique sont ci-dessous. Lis d'abord `CLAUDE.md` et `MEMORY.md`, puis ce fichier.

État au moment de l'écriture : branche `development`, dernier commit poussé `a017571` (vérifier avec `git log --oneline -5`). Suite de tests : 1711 exemples, 97,26 % de couverture, un seul échec connu et flaky (voir "Pièges").

---

## 1. Ce qui existe déjà (ne pas refaire)

Base préexistante : partie double avec contraintes en base, factures clients/fournisseurs (multi-devises), partenaires, lettrage, rapprochement bancaire (import CAMT), lots de paiement SEPA pain.001, Peppol (UBL), analytique, exercices fiscaux et clôture, rapports (balance, bilan, résultat, balance âgée, grand livre, exports CSV/xlsx dans `ReportsController`).

Travail TVA de la session précédente (tout commité et poussé) :

| Sujet | Où |
|---|---|
| Catalogue de grilles TVA (libellés anglais, mapping taux→grille) | `app/services/accounting/vat_grid.rb` |
| Comptes TVA corrigés : 410100 (à récupérer), 450100 (à payer), 640400 (TVA non déductible) | `app/services/accounting/account_codes.rb`, seeds `db/seeds/pcmn_*.json` |
| Taux 0 %, montants de base réellement stockés dans les grilles | `generate_invoice_journal_entry.rb` |
| Numéros de TVA UE (27 formats), `Partner#eu_country?`/`#domestic?` | `app/models/accounting/partner.rb` |
| `Invoice#vat_treatment` (domestic, intracom_goods, intracom_services, construction_reverse_charge, export, exempt), double ligne TVA due/déductible en cocontractant | `invoice.rb`, `generate_invoice_journal_entry.rb` |
| Réglages entité : `vat_filing_frequency`, `vat_regime`, `vat_scheme`, `vat_prorata_rate` + écran Settings > VAT Settings | `entity.rb`, `Accounting::Settings::VatSettingsController` |
| Prorata de déduction (part non déductible en 640400) | `generate_invoice_journal_entry.rb#build_deductible_vat_lines` |
| Régularisation annuelle du prorata | `Accounting::Actions::RegularizeVatProrata` |
| Immobilisations et révision TVA 5/15 ans | `Accounting::FixedAsset`, `Accounting::Actions::ReviewFixedAssetVat`, écran CRUD "Fixed Assets" |
| Page "Year-end VAT regularization" (sous Fiscal Years, visible si `vat_scheme_mixed?`) | `FiscalYearsController#vat_regularization` |
| Workflow déclaration (draft → submitted → accepted), export XML | `VatDeclaration#submit!/#accept!`, `Accounting::BuildIntervatXml` |
| Relevé intracommunautaire trimestriel | `Accounting::IntracomListing(+Line)`, `IntracomListingQuery`, `GenerateIntracomListing` |
| Migration de backfill des comptes PCMN pour entités existantes | `db/migrate/20260923150000_*` |

Vérifié à la main dans l'app réelle (bin/dev + navigateur) : facture fournisseur intracom_services (écriture équilibrée, grilles 56/59/87), facture client intracom_goods, déclaration TVA, workflow submit, relevé intracom, régularisation prorata (calcul vérifié : 2130 × 80 % → 426 à reverser), révision d'immobilisation (1000 × 15 pts → 150 récupérés, grille 62).

---

## 2. Conventions et pièges du projet (à respecter)

**Processus**
- TDD strict : écrire le test, le voir échouer pour la bonne raison, puis coder. Un test qui passe du premier coup est suspect (cela m'est arrivé : un défaut DB masquait le RED).
- Interface entièrement en anglais. La conversation avec l'utilisateur est en français.
- Le mode "ponytail" est actif : solution la plus simple qui marche, pas d'abstraction spéculative.
- Ne committer que sur demande explicite, ne pousser que sur demande explicite. Ne jamais ajouter `coverage/` aux commits (fichiers modifiés à chaque run de tests). Les messages de commit se terminent par `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- Style : `bin/rubocop` sur les fichiers touchés. Faux positifs normaux : rubocop "lint" les `.erb` et `.yml` comme du Ruby. `spec/services/accounting/actions/generate_invoice_journal_entry_spec.rb` a des offenses préexistantes (espaces dans les crochets).

**Tests**
- La suite complète dure ~2 min 30 : la lancer en arrière-plan (`run_in_background`), le timeout par défaut est de 2 min.
- Flaky connu et sans rapport : `spec/services/bank/simulator/grouped_receipt_spec.rb:20` (passe seul, échoue parfois dans la suite).
- SimpleCov (95 %) n'a de sens que sur la suite complète.
- Contextes partagés : `'with entity'`, `'with_open_fiscal_year'`, `'with_pcmn_accounts'` (crée 604, 440, 400, 410100, 700, 450100, 550, 570, 651200, 751100, 640400 — ajouter ici tout nouveau compte requis).
- Les specs de requête utilisent `sign_in user` avec `create(:user_entity, :accountant, user:, entity:)`.

**Architecture**
- Multi-tenant : `acts_as_tenant :entity`. En contrôleur/service, `ActsAsTenant.current_tenant` donne l'entité. Il n'y a pas d'helper `current_entity` dans les vues.
- LightService : les Organizers ont `.call` ; une Action (`extend LightService::Action`) n'a PAS de `.call` autonome. Pour un service unitaire, faire une classe simple qui retourne `LightService::Context.make(...)` (voir `RegularizeVatProrata`, `ReverseJournalEntry`).
- Pundit : chaque ressource doit avoir sa classe de policy, même vide (`class X < ApplicationPolicy; end`). Attention : `InvoicePolicy`, `FiscalYearPolicy`… utilisent `user.admin? || user.accountant?` (rôle global), alors que `ApplicationPolicy` utilise l'appartenance à l'entité. Les écrans Settings sont protégés par `Accounting::Settings::BaseController`.
- Écritures comptables : la contrainte DB `enforce_double_entry` est vérifiée à chaque ligne. Dans une transaction, exécuter `ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")` avant de créer les lignes. `entry.post!` (AASM via `Accounting::Statusable`) exige une `reference` non vide hors brouillon.
- `JournalEntryLine.vat_code` = numéro de grille (entier) ; `vat_amount` porte la BASE pour les grilles de base et le montant de TVA pour les grilles de TVA. `VatGridQuery` additionne `vat_amount` par `vat_code` (sans signe).
- Devises : débit/crédit toujours en EUR, `amount_currency` + `exchange_rate` conservent l'original.
- Les totaux de facture ne sont calculés qu'au postage (`compute_totals`) ; en brouillon ils valent 0. Pour un régime non domestique, `total_incl_vat` = HT (la TVA n'est pas facturée) mais `vat_amount` reste calculé (autoliquidation).
- Base de données : `db/structure.sql` (format SQL), migrations Rails 8.1. Après migration, structure.sql se régénère ; le commiter.
- Nouveaux comptes PCMN : ajouter aux deux seeds JSON, à `AccountCodes`, ET écrire une migration de backfill (les entités existantes ne reçoivent jamais les nouveaux comptes des seeds — c'est un bug réel déjà rencontré : `Couldn't find Accounting::Account`).
- i18n : `config/locales/en.yml` ; vérifier l'absence de clés dupliquées au même niveau (une clé `show:` dupliquée a fait afficher "Title" au lieu du titre). La plupart des vues codent l'anglais en dur ; les libellés de bouton "View" sont en dur.
- Formatage monétaire : `Accounting::MoneyPresenter#format` → `1 000,00 €` (espace comme séparateur de milliers).

**Vérification manuelle dans l'app**
- Base de dev : le PostgreSQL 18 du système sur le port 5432 (`ledgerflow` / `password`), déjà migré. `docker compose up` échoue (port pris) et n'est pas nécessaire.
- Démarrer avec `bin/dev` en arrière-plan ; le journal de requêtes est `log/development.log`. Utilisateurs de démo : `admin@ledgerflow.test`, `comptable@ledgerflow.test`, `manager@…`, `auditeur@…`, `budget@…`, mot de passe `password123!`.
- Champs date HTML : cliquer sur le segment jour (extrémité gauche) puis taper les chiffres d'une traite (`02022026`). Vérifier chaque saisie par capture d'écran : la page défile et les clics par coordonnées dérivent.
- `psql -c "a; b; c"` exécute tout dans UNE transaction : une erreur annule toutes les instructions précédentes malgré les "DELETE n" affichés.
- Nettoyer les données de test créées (partenaires, factures, écritures, listings) une fois la vérification terminée.

---

## 3. Écarts à traiter, par priorité

Constats vérifiés par recherche dans le code : aucun type d'avoir, aucune génération PDF (`prawn`, `prawn-table`, `ferrum` sont dans le Gemfile mais inutilisés), aucun amortissement, aucune relance, aucun envoi de facture par mail, aucune route d'édition de l'entité (`resources :entities, only: %i[index new create]`).

### P0 — bloquants pour un usage réel

**#1 Notes de crédit (avoirs)**
- Aujourd'hui `Invoice#invoice_type` ne vaut que `customer` ou `supplier`. Corriger une facture postée impose de l'annuler.
- Piste : ajouter un type de document (facture / avoir) et un lien `credited_invoice_id`. Le postage inverse les sens débit/crédit ; l'avoir peut être imputé sur la facture d'origine via le lettrage existant (`Accounting::Lettering`, `LineAllocation`) — `stale_credits_query.rb` et `aged_balance_query.rb` manipulent déjà des crédits non imputés.
- Décision de conception à prendre tôt : `VatGridQuery` additionne sans signe. Soit les lignes d'avoir portent des `vat_amount` négatifs dans les grilles existantes, soit elles vont dans des grilles dédiées. Les grilles officielles pour les avoirs (ventes et achats) sont à confirmer avec un comptable ; ne pas les inventer.
- Doit couvrir : avoir partiel, avoir sur facture en devise, avoir sous régime cocontractant/intracom (impact sur le relevé intracom), avoir sur facture déjà payée, PDF/Peppol (UBL CreditNote), rapports (balance âgée).

**#2 Conformité de la déclaration TVA**
- Les grilles 46, 47, 48, 49 (ventes) et 86, 87, 88 (achats) sont des codes INTERNES approximatifs. Attention : 48 et 49 ont une signification officielle différente (avoirs) qui entrera en collision avec l'implémentation des avoirs.
- Les grilles 81/82/83 sont aujourd'hui ventilées par taux (21/12/6 %), alors que la déclaration officielle les ventile par nature d'achat (marchandises, services/divers, biens d'investissement). La colonne `accounting_accounts.vat_code_default` existe, n'est jamais alimentée ni utilisée, et est le bon support pour classer chaque compte de charge.
- Les grilles de total (dont 71/72, solde à payer ou à récupérer) ne sont pas calculées.
- `BuildIntervatXml` est calqué de mémoire sur la structure publique "VATConsignment" et n'a jamais été validé contre le XSD officiel.
- Le listing annuel des clients assujettis (distinct du relevé intracom trimestriel) n'existe pas — à confirmer avec le comptable.
- Livrable attendu : tableau officiel des grilles validé par un comptable, refonte de `VatGrid`, calcul des totaux, validation XSD dans un test.

**#3 Facture imprimable et envoyée**
- Générer un PDF de facture (Prawn + prawn-table, ou HTML→PDF via Ferrum) avec : entité (adresse, TVA, IBAN via `BankAccount`), partenaire, lignes, TVA par taux, mentions légales obligatoires du régime (ex. "Autoliquidation" pour le cocontractant), communication structurée (`Accounting::StructuredCommunication` existe).
- Envoi par mail (ActionMailer + jobs Solid Queue déjà en place) avec suivi de statut.

### P1 — nécessaires pour une PME

**#4 Amortissements**
- `FixedAsset` ne contient que la TVA initiale. Il manque : valeur d'acquisition, compte d'immobilisation, date de mise en service, méthode (linéaire/dégressif), durée, valeur résiduelle, plan d'amortissement, écritures (dotation en classe 63, amortissements actés en 2xxxx9) via un service annuel/mensuel dans le journal OD, gestion de la cession (sortie d'actif, plus/moins-value). S'intégrer à `CloseFiscalYear`.
- Le lien `invoice_line_id` (optionnel) existe : envisager de créer l'immobilisation depuis une ligne de facture d'achat.

**#5 Comptes annuels** : bilan et compte de résultat au format de dépôt (schéma BNB, abrégé/micro selon la taille), checklist de clôture guidée, annexes. Sujet volumineux : commencer par une recherche et un cadrage avec un comptable.

**#6 Relances clients** : modèle de relance (niveaux, gabarits), sélection à partir de `AgedBalanceQuery`, envoi par mail (dépend de #3), historique par facture.

**#7 Édition de l'entité** : ajouter `edit`/`update` (nom, dénomination, numéro de TVA, adresse, forme juridique, pays). L'écran VAT Settings existant (`Accounting::Settings::VatSettingsController`) peut servir de modèle et être fusionné dans une page "Entity settings".

### P2 — simplicité pour un non-comptable

- **#8** Le formulaire de facture affiche un total faux pour les régimes non domestiques (1 210 € affichés, 1 000 € dus). Corriger `app/javascript/controllers/invoice_form_controller.js` (`computeInvoiceTotals`) pour tenir compte du select `vat_treatment`.
- **#9** Aide contextuelle sur `vat_treatment`, le prorata, la franchise.
- **#10** Mode "indépendant en franchise" simplifié (masquer TVA, grilles, régularisations quand `vat_regime_franchise?`).
- **#11** Formulaire de facture plus léger : modèles, factures récurrentes, saisie de date fiable, dupliquer une facture.
- Pas d'UI pour lancer la revue des immobilisations hors de la page de régularisation ; pas de rappel automatique de fin d'année.

### P3 — à vérifier avant tout lancement

- Sauvegardes et restauration, revue de sécurité en production (`bin/brakeman`, `bin/bundler-audit`), reprise des soldes d'ouverture, import depuis un autre logiciel comptable.
- Corriger le flaky `grouped_receipt_spec`.
- **Validation par un comptable belge d'un cycle complet réel** (facture, avoir, TVA, clôture) : sans cela, ne pas parler de produit "prêt".

---

## 4. Ordre de travail recommandé

1. #1 Avoirs (touche le modèle comptable : le plus tôt possible), en réservant la décision sur les grilles au point #2.
2. #3 PDF + envoi (débloque #6).
3. #2 Conformité TVA, avec un comptable.
4. #4 Amortissements, puis #7, puis #5/#6.
5. Lot P2 en fin de parcours, ou au fil de l'eau.

Chaque point devrait suivre : brainstorming court → plan → TDD → vérification manuelle dans l'app → commit. Faire valider les décisions de modèle de données (notamment #1, #2, #4) par l'utilisateur avant de coder.

## 5. Questions ouvertes à poser à l'utilisateur au démarrage

1. Un comptable belge est-il disponible pour valider le tableau des grilles (#2) et un cycle complet (P3) ?
2. Public visé en premier : PME avec comptable externe, ou indépendant seul ? Cela change la priorité de #5, #9, #10.
3. Envoi de factures : SMTP, service transactionnel, ou Peppol uniquement ?
4. Hébergement cible (Kamal est configuré) et politique de sauvegarde ?

## 6. Prompt de démarrage suggéré pour la nouvelle conversation

> Lis `CLAUDE.md`, `MEMORY.md` et `docs/dev/HANDOFF_next_steps.md`. Nous reprenons LedgerFlow pour combler les écarts listés en section 3. Commence par le point #1 (notes de crédit) : propose-moi un plan court (modèle de données, sens des écritures, impact TVA/lettrage/rapports) avant de coder, puis travaille en TDD strict.

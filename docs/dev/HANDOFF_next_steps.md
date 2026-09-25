# LedgerFlow — Dossier de reprise (nouvelle conversation)

Objectif de la prochaine session : combler les écarts qui séparent LedgerFlow d'un outil qu'une PME ou un indépendant belge peut utiliser seul. La liste priorisée et le contexte technique sont ci-dessous. Lis d'abord `CLAUDE.md` et `MEMORY.md`, puis ce fichier.

État au moment de l'écriture : branche `development`, dernier commit poussé `a017571` (vérifier avec `git log --oneline -5`). Suite de tests : 2008 exemples, 97,69 % de couverture (après avoirs, édition de l'entité, PDF, e-mail, amortissements, totaux du formulaire de facture et immobilisations depuis une facture), un seul échec connu et flaky (voir "Pièges").

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
- Pour tester du JavaScript (Stimulus), écrire un spec système `type: :system, js: true` (Capybara + Chrome headless, `spec/support/system.rb`) : il tourne ici sans configuration supplémentaire. Se connecter avec `login_as user, scope: :user`. Comparer des **nombres** extraits du texte (`gsub(/[^\d,]/, '')`) plutôt que des chaînes formatées, le JS et le serveur n'écrivent pas la devise pareil.
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
- Ne jamais lancer deux `rspec` en même temps (même base de test, `DatabaseCleaner` tronque au démarrage : deadlock, résultats faussés). `pgrep -f "bundle exec rspec"` se reconnaît lui-même : se fier à la notification de fin de tâche.
- Automatisation Chrome : si une capture expire (« renderer may be frozen ») ou si des clics restent sans effet, lire `document.visibilityState` : un onglet `hidden` (fenêtre masquée) ne peint pas et ne reçoit pas les clics. Demander de mettre Chrome au premier plan, et vérifier un clic par le `POST` dans `log/development.log`.
- Les journaux d'audit sont immuables (trigger) : le nettoyage de données de test laisse leurs lignes d'audit.
- Base de dev : le PostgreSQL 18 du système sur le port 5432 (`ledgerflow` / `password`), déjà migré. `docker compose up` échoue (port pris) et n'est pas nécessaire.
- Démarrer avec `bin/dev` en arrière-plan ; le journal de requêtes est `log/development.log`. Utilisateurs de démo : `admin@ledgerflow.test`, `comptable@ledgerflow.test`, `manager@…`, `auditeur@…`, `budget@…`, mot de passe `password123!`.
- Champs date HTML : cliquer sur le segment jour (extrémité gauche) puis taper les chiffres d'une traite (`02022026`). Vérifier chaque saisie par capture d'écran : la page défile et les clics par coordonnées dérivent.
- `psql -c "a; b; c"` exécute tout dans UNE transaction : une erreur annule toutes les instructions précédentes malgré les "DELETE n" affichés.
- Nettoyer les données de test créées (partenaires, factures, écritures, listings) une fois la vérification terminée.

---

## 3. Écarts à traiter, par priorité

Constats vérifiés par recherche dans le code : aucun type d'avoir, aucune génération PDF (`prawn`, `prawn-table`, `ferrum` sont dans le Gemfile mais inutilisés), aucun amortissement, aucune relance, aucun envoi de facture par mail, aucune route d'édition de l'entité (`resources :entities, only: %i[index new create]`).

### P0 — bloquants pour un usage réel

**#1 Notes de crédit (avoirs) — FAIT (commit `aa2ee55`, 2026-09-24)**
- Modèle : `Invoice#document_type` (`invoice`/`credit_note`) et `credited_invoice_id` optionnel. Les lignes d'avoir sont positives ; le postage (`GenerateInvoiceJournalEntry#create_line`) inverse le sens et le signe de `vat_amount`, donc `VatGridQuery` sort des grilles nettes sans grille dédiée.
- Validations : même partenaire, type et régime TVA que la facture créditée, facture postée, plafond cumulé (`ValidateCreditNoteAmount`). Numérotation : même séquence que les factures.
- Imputation : `Accounting::ApplyCreditNote` (via `AllocateLines`), bouton « Apply to invoice ». **Refusée si des encaissements sont déjà enregistrés sur la facture** : `BookInvoiceReceipt` ne lettre pas la ligne client, son `open_amount` resterait plein.
- Aussi couvert : relevé intracom net des avoirs, lots SEPA excluent les avoirs, Peppol envoi (`CreditNote` 381 + `BillingReference`) et réception, `remaining_amount` tient compte des avoirs, annulation d'une facture créditée refusée, rapprochement bancaire ignore les avoirs.
- À traiter plus tard :
  - **Remboursement d'un avoir sur facture déjà encaissée** : l'avoir reste non imputé (visible en « unallocated » de la balance âgée) ; le flux de remboursement (rapprochement bancaire, ou lettrage manuel) n'est ni conçu ni vérifié.
  - Grilles officielles pour les avoirs (48/49 ventes, 85 achats) : à confirmer avec un comptable, voir #2.
  - Cosmétique : l'écriture d'un avoir s'intitule « Invoice … », la page brouillon propose « Post invoice » / « Cancel invoice ».
  - Les annotations analytiques ne sont pas copiées de la facture vers l'avoir préremplie.
  - Le formulaire d'édition redirige vers l'édition après « Create credit note » ; la TVA des lignes était mal préselectionnée (corrigé dans le même commit).
  - Pas de PDF d'avoir (dépend de #3).

**#2 Conformité de la déclaration TVA**
- Les grilles 46, 47, 48, 49 (ventes) et 86, 87, 88 (achats) sont des codes INTERNES approximatifs. Attention : 48 et 49 ont une signification officielle différente (avoirs) qui entrera en collision avec l'implémentation des avoirs.
- Les grilles 81/82/83 sont aujourd'hui ventilées par taux (21/12/6 %), alors que la déclaration officielle les ventile par nature d'achat (marchandises, services/divers, biens d'investissement). La colonne `accounting_accounts.vat_code_default` existe, n'est jamais alimentée ni utilisée, et est le bon support pour classer chaque compte de charge.
- Les grilles de total (dont 71/72, solde à payer ou à récupérer) ne sont pas calculées.
- `BuildIntervatXml` est calqué de mémoire sur la structure publique "VATConsignment" et n'a jamais été validé contre le XSD officiel.
- Le listing annuel des clients assujettis (distinct du relevé intracom trimestriel) n'existe pas — à confirmer avec le comptable.
- Livrable attendu : tableau officiel des grilles validé par un comptable, refonte de `VatGrid`, calcul des totaux, validation XSD dans un test.

**#3 Facture imprimable et envoyée** — découpé en 3 sous-projets ; **3a fait**, 3b et 3c à faire.
- **3a PDF — FAIT (2026-09-24)** : `Accounting::InvoicePdf` (Prawn, anglais uniquement), `GET /accounting/invoices/:id/pdf`, bouton « Download PDF » sur les factures et avoirs clients émis. Émetteur lu depuis l'entité, IBAN/BIC du premier `BankAccount` actif, communication structurée pour les factures (pas les avoirs), mention légale générique par `vat_treatment` et pour la franchise. Dépendance de test ajoutée : `pdf-reader`. Limites : caractères hors Windows-1252 remplacés par `?` (police Helvetica intégrée), un seul compte bancaire, pas de logo ; **les mentions légales sont génériques, sans article du Code TVA : à faire valider par un comptable**.
- **3b Envoi par e-mail — FAIT en mode test (2026-09-24)** : table `accounting_invoice_emails` (destinataire, sujet, statut queued/sent/failed, erreur, auteur), `Accounting::SendInvoiceEmail` (crée l'envoi et met `Accounting::InvoiceEmailJob` en file), `Accounting::InvoiceMailer` (texte anglais, PDF de `InvoicePdf` en pièce jointe), carte « Emails » sur les factures/avoirs clients émis (destinataire prérempli avec `Partner#email` et modifiable, historique avec statut et erreur), rôles admin/comptable. Le job prend l'**id** (pas un GlobalID) : `ActsAsTenant.require_tenant` est vrai et un job n'a pas de tenant. `Invoice#issued?` (posted/partially_paid/paid) remplace la condition dupliquée. En développement, les e-mails sont écrits dans `tmp/mails/` (`delivery_method = :file`) ; en test, `:test`.
  - **À FAIRE pour la production (paramètres SMTP fournis par l'utilisateur le moment venu)** : renseigner `config.action_mailer.smtp_settings` dans `config/environments/production.rb` (credentials `smtp` via `bin/rails credentials:edit`), définir la variable d'environnement `MAILER_FROM` (adresse d'expédition ; le défaut `invoices@ledgerflow.example` n'est valable qu'en dev/test) et l'hôte de `default_url_options` (aujourd'hui `example.com`). `raise_delivery_errors` est déjà `true` : sans SMTP, un envoi est enregistré `failed` avec son erreur (vérifié).
  - Limites : pas de relance automatique d'un envoi `failed` (l'utilisateur renvoie à la main), un seul destinataire, pas de corps personnalisable, texte seul.
- **3c Peppol — À FAIRE, après choix de l'Access Point** : l'intégration actuelle (`Peppol::Actions::SendToDigiteal`, `Peppol::WebhooksController`) est un squelette écrit de mémoire, jamais validé contre une vraie API ni un compte Digiteal. Manques constatés : pas d'`EndpointID` (identifiant Peppol, en Belgique `0208:` + numéro d'entreprise) dans l'UBL, aucun identifiant Peppol sur l'entité ni sur les partenaires, émetteur lu dans des constantes d'environnement (`PEPPOL_COMPANY_*`) et non depuis l'entité, réception d'une facture rattachée à un exercice/entité choisi arbitrairement (`FiscalYear.current` sans tenant). L'utilisateur veut comprendre le fonctionnement de Peppol avant de décider : expliquer (réseau d'Access Points, identifiants dans un annuaire, format UBL BIS 3.0), puis lire la vraie documentation de l'AP choisi avant de recoder. À ma connaissance la facturation électronique B2B via Peppol est obligatoire en Belgique depuis le 1er janvier 2026 (à vérifier).

### P1 — nécessaires pour une PME

**#4 Amortissements** — découpé en 3 sous-projets ; **4a et 4b faits**, 4c à faire.
- **4a Amortissement linéaire annuel — FAIT (2026-09-25)** : `FixedAsset` étendu (valeur d'acquisition, `asset_account`, `in_service_date`, `useful_life_years`, `residual_value`, `depreciation_method` = `linear`) ; la TVA initiale peut valoir 0. Comptes déduits du compte d'immobilisation (`FixedAsset::DEPRECIATION_ACCOUNTS` : 21→630100/219000, 22→630200/229000, 23→630200/239000, 24→630200/249000 ; terrains `220100` exclus) : **tous déjà dans les seeds PCMN, aucune migration de rattrapage**. Calcul prorata temporis au mois à partir du mois de mise en service : les montants cumulés sont arrondis (pas les annuels), donc la somme du plan égale exactement la base (`depreciation_for(fiscal_year)`, `depreciation_plan` par année civile, affichage seulement). `Accounting::PostDepreciation` : une écriture d'OD par immobilisation (`DEP-ASSET-<id>-<année>`, date de fin d'exercice), idempotente et tout-ou-rien, tracée par `Accounting::DepreciationEntry` (unique par immobilisation et exercice) ; refuse un exercice clos, accepte `pre_closing`. `CloseFiscalYear` est **bloquée** par `Actions::ValidateDepreciationPosted` tant qu'une dotation est due. UI : champs dans le formulaire, tableau « Depreciation <année> » et bouton « Post depreciation » sur Fixed Assets (comptable), plan complet sur la page d'édition. Supprimer une immobilisation déjà amortie affiche un message (`restrict_with_error`).
  - Hypothèses à raffiner : un bien cédé est amorti jusqu'au mois de cession inclus (à revoir en 4b) ; le plan affiché suit les années civiles alors que la comptabilisation suit les vrais exercices ; l'immobilisation n'est pas encore créée depuis une facture d'achat (4c) ; l'écran d'index annonce encore « VAT review » seulement dans son texte d'état vide.
  - Piège de test découvert en 4b : un test qui crée une dotation antérieure pour un bien cédé doit la rattacher à un exercice **antérieur**, pas à celui de la cession (règle « déjà amorti pour l'année »).
- **4b Cession — FAIT (2026-09-25)** : `Accounting::DisposeFixedAsset` (tout ou rien) : (1) comptabilise la dotation de l'exercice de cession jusqu'au mois de cession inclus, **datée à la date de cession** (`PostDepreciation.post` est maintenant public et date ainsi ce cas) ; (2) écriture de sortie `DISPOSAL-ASSET-<id>` à la date de cession : D amortissements cumulés (2x9000), D `660100` (`AccountCodes::ASSET_DISPOSAL`) pour la VNC (coût moins cumul, le résiduel reste dans la VNC, pas de ligne si VNC nulle), C compte d'immobilisation au coût ; (3) `disposed_on` et `disposal_journal_entry_id` (nouvelle colonne). Refus : bien non amortissable, déjà cédé, date avant la mise en service, aucun exercice couvrant la date, exercice clos, dotation d'un exercice **antérieur** non comptabilisée (message nommant l'année), dotation de l'année déjà comptabilisée pour toute l'année. **Présentation brute** : le prix de vente n'est PAS comptabilisé par la cession ; l'utilisateur émet une facture client avec une ligne sur `760100` pour le prix, et le résultat apparaît comme 760100 moins 660100 (mise au rebut : pas de facture). UI : lien « Dispose » dans l'index (comptable, bien amortissable non cédé), page `disposal` (explication, date, confirmation) et action `dispose`. Garde-fou : pour un bien amortissable, `disposed_on` ne se saisit plus dans le formulaire d'édition (validation « use Dispose ») ; il reste libre pour les biens suivis pour la seule révision de TVA, et la régularisation de TVA de l'année de cession ne change pas.
  - À faire valider par un comptable : le compte `660100` (« Moins-values ») reçoit ici la VNC sortie et non une moins-value calculée ; l'amortissement du mois de cession est compté en entier.
  - Hors périmètre : cession partielle ; annulation d'une cession (corriger par écritures manuelles) ; lien facture-immobilisation et calcul automatique de la plus ou moins-value ; cession d'un bien dont l'amortissement de l'année a déjà été comptabilisé pour toute l'année (il faut d'abord l'extourner, pas d'outil d'extourne des dotations).
- **4c Extensions** : **création depuis une ligne de facture d'achat — FAIT (2026-09-25)** ; dégressif, mensuel et réductions de valeur restent à faire (voir plus bas).
  - Fait : sur une facture fournisseur émise (hors avoir), une ligne posée sur un compte d'immobilisation amortissable offre « Create fixed asset » (lien « Fixed asset » ensuite). `FixedAsset.build_from_invoice_line(line)` préremplit : description, date de la facture, valeur d'acquisition et TVA déduite **en EUR** (× taux de change), TVA × prorata de l'entité (100 % par défaut), catégorie (immeuble pour un compte 22x), compte de la ligne. `FixedAsset.asset_purchase_line?` et `FixedAsset.depreciable_account?` sont les prédicats partagés (contrôleur, vue, validation). Règles : une immobilisation par ligne (validation + index unique partiel `invoice_line_id`), le compte d'immobilisation doit être celui de la ligne (le coût est déjà débité dessus par la facture, la cession le crédite : il n'est pas modifiable dans le formulaire), refus pour brouillon, facture client, avoir ou compte non amortissable. **`CancelInvoice` refuse d'annuler une facture dont une ligne a créé une immobilisation** (« delete the asset first »). L'index des immobilisations a une colonne « Invoice ». Aucun changement du moteur d'écritures : la facture a déjà comptabilisé le coût, le lien ne crée que la fiche du registre.
  - Limites : une immobilisation par ligne (pas par unité) ; pas de rattachement après coup d'une immobilisation existante à une ligne ; la TVA déduite préremplie est calculée par ligne et peut différer de quelques centimes de l'écriture (arrondi par taux) : le champ reste modifiable.
  - Reste à faire dans 4c : **dégressif** (taux double du linéaire plafonné, bascule vers le linéaire ; les conditions légales belges sont à faire valider par un comptable avant de coder), **comptabilisation mensuelle** (change la granularité de `DepreciationEntry`, unique par immobilisation et exercice) ; les **réductions de valeur** (631xxx) ne sont pas de l'amortissement d'immobilisation et sont à traiter avec la clôture (#5).

**#5 Comptes annuels** : bilan et compte de résultat au format de dépôt (schéma BNB, abrégé/micro selon la taille), checklist de clôture guidée, annexes. Sujet volumineux : commencer par une recherche et un cadrage avec un comptable.

**#6 Relances clients** : modèle de relance (niveaux, gabarits), sélection à partir de `AgedBalanceQuery`, envoi par mail (dépend de #3), historique par facture.

**#7 Édition de l'entité — FAIT (2026-09-24)** : écran Settings > Entity (`Accounting::Settings::EntitiesController`), format du numéro de TVA validé (`Partner.valid_vat_number?`, partagé), un numéro vide est stocké en NULL (`Entity` `normalizes`, l'index unique partiel ne saute que les NULL). VAT Settings reste un écran séparé (pas fusionné).

### P2 — simplicité pour un non-comptable

- **#8 — FAIT (2026-09-25)** : le formulaire de facture suit maintenant `vat_treatment` comme `Invoice#compute_totals` : sous un régime non domestique, TVA affichée à 0,00 (ligne et total), total = HT, et un avis « VAT is not charged to the partner under this VAT treatment ». `invoice_form_controller.js` : `chargesVat()`, `onVatTreatmentChanged()`, `recomputeAll()` et un `connect()` qui recalcule au chargement (avant, les totaux d'une facture en brouillon s'affichaient à 0,00 en édition, et les lignes d'un brouillon non domestique montraient la TVA du serveur). Testé par `spec/system/accounting/invoice_form_totals_spec.rb` (Chrome headless, 11 exemples). Reste dans le formulaire : le JS affiche le code devise (« 1 000,00 EUR ») là où le serveur affiche « € ».
- **#9** Aide contextuelle sur `vat_treatment`, le prorata, la franchise.
- **#10** Mode "indépendant en franchise" simplifié (masquer TVA, grilles, régularisations quand `vat_regime_franchise?`).
- **#11** Formulaire de facture plus léger : modèles, factures récurrentes, saisie de date fiable, dupliquer une facture.
- Pas d'UI pour lancer la revue des immobilisations hors de la page de régularisation ; pas de rappel automatique de fin d'année.

### P3 — à vérifier avant tout lancement

- Sauvegardes et restauration, revue de sécurité en production (`bin/brakeman`, `bin/bundler-audit`), reprise des soldes d'ouverture, import depuis un autre logiciel comptable.
- **Compte 699000 (résultat de l'exercice) — CORRIGÉ (2026-09-25)** : il n'était dans aucun seed PCMN ni créé à la création d'une entité, donc `CloseFiscalYear` échouait (« account 699000 not found ») sur toute entité neuve. Ajouté aux deux seeds (`pcmn_asbl.json` au format compact une ligne par compte, `pcmn_commercial.json` indenté : insérer dans le style de chaque fichier), migration de rattrapage `20260925100000` (relance `PcmnSeeder`), et deux gardes : une entité neuve (ASBL ou SRL) peut clore son exercice, et tout code de `Accounting::AccountCodes` doit exister dans les deux PCMN (`spec/lib/seeders/pcmn_seeder_spec.rb`). Piège à retenir : un aller-retour JSON reformate le seed ASBL.
- Corriger le flaky `grouped_receipt_spec`.
- **Validation par un comptable belge d'un cycle complet réel** (facture, avoir, TVA, clôture) : sans cela, ne pas parler de produit "prêt".

---

## 4. Ordre de travail recommandé

1. ~~#1 Avoirs~~ (fait), en réservant la décision sur les grilles au point #2.
2. #3 PDF + envoi (débloque #6) : 3a PDF et 3b e-mail (mode test) faits ; reste la config SMTP de production, puis 3c Peppol.
3. #2 Conformité TVA, avec un comptable.
4. #4 Amortissements (4a et 4b faits ; 4c à faire), ~~#7~~ (fait), puis #5/#6.
5. Lot P2 en fin de parcours, ou au fil de l'eau.

Chaque point devrait suivre : brainstorming court → plan → TDD → vérification manuelle dans l'app → commit. Faire valider les décisions de modèle de données (notamment #1, #2, #4) par l'utilisateur avant de coder.

## 5. Questions ouvertes à poser à l'utilisateur au démarrage

1. Un comptable belge est-il disponible pour valider le tableau des grilles (#2) et un cycle complet (P3) ?
2. Public visé en premier : PME avec comptable externe, ou indépendant seul ? Cela change la priorité de #5, #9, #10.
3. Envoi de factures : SMTP, service transactionnel, ou Peppol uniquement ?
4. Hébergement cible (Kamal est configuré) et politique de sauvegarde ?

## 6. Prompt de démarrage suggéré pour la nouvelle conversation

> Lis `CLAUDE.md`, `MEMORY.md` et `docs/dev/HANDOFF_next_steps.md`. Nous reprenons LedgerFlow pour combler les écarts listés en section 3. Commence par le point #1 (notes de crédit) : propose-moi un plan court (modèle de données, sens des écritures, impact TVA/lettrage/rapports) avant de coder, puis travaille en TDD strict.

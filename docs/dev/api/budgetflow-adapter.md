# Spécification : adaptateur `ledgerflow` pour BudgetFlow

Statut : **implémenté dans BudgetFlow** (2026-09-29, accord explicite de l'utilisateur) : `app/services/accounting/ledgerflow/{exporter,client}.rb` et ses specs, adaptateur `ledgerflow` déclaré dans `Accounting::Factory` et `EntitySetting`. Les corps JSON produits ont été vérifiés contre la vraie API de LedgerFlow (fournisseur, facture EUR et USD, avoir, annulation, rejeux). La **synchronisation des paiements** (LedgerFlow → BudgetFlow, section 9) est implémentée aussi : `payment_sync.rb`, `system_user.rb`, tâche récurrente, e-mail d'alerte. Ce document reste la référence du contrat.
Sources lues (lecture seule) : `budgetflow/app/services/accounting/` (`base.rb`, `factory.rb`, `dolibarr/exporter.rb`), `db/schema.rb`, `app/models/{invoice,entity_setting}.rb`.
Contrat côté LedgerFlow : `docs/dev/api/inbound-api.md`.

## 1. Idée

BudgetFlow exporte déjà ses factures vers un logiciel comptable par des **adaptateurs** qui implémentent `Accounting::Base`. LedgerFlow n'a pas besoin d'un client sortant : il suffit d'ajouter un adaptateur `ledgerflow` (à côté de `dolibarr`, `winbooks`, `null`) qui appelle l'API entrante de LedgerFlow. BudgetFlow reste maître de l'envoi ; LedgerFlow ne l'appelle jamais. Les **paiements**, eux, se gèrent dans LedgerFlow : BudgetFlow les apprend en interrogeant un flux d'événements (section 9).

## 2. Configuration

Par entité BudgetFlow (`EntitySetting`, déjà présent) :

| Champ BudgetFlow | Valeur |
|---|---|
| `accounting_adapter` | `ledgerflow` (à ajouter à `Accounting::Factory::ADAPTERS` et à la liste `ACCOUNTING_ADAPTERS`) |
| `accounting_api_url` | URL de base de LedgerFlow, sans `/api/v1` |
| `accounting_api_key` | Clé `lf_…` d'un client API créé dans *Settings → API Clients* de LedgerFlow |
| `accounting_api_timeout` | 30 s (défaut existant) |

Une entité BudgetFlow correspond à **un client API** et donc à **une entité comptable** LedgerFlow (la clé fixe l'entité). Scopes à accorder : `partners:write`, `invoices:write`, `invoices:read`.

## 3. Correspondance des méthodes

| `Accounting::Base` | Appel LedgerFlow | Remarques |
|---|---|---|
| `health_check(entity_setting)` | `GET /api/v1/ping` | `200 {"status":"ok","entity":…,"api_client":…,"scopes":[…]}`. `401` : clé invalide ou révoquée. Vérifier aussi que les 3 scopes sont présents. |
| `upsert_third_party(supplier)` | `PUT /api/v1/partners/{ref}` | Idempotent. À appeler à la création et à la modification du fournisseur. |
| `export_invoice(invoice)` | `PUT /api/v1/invoices/{ref}` | Envoyer d'abord le fournisseur (idempotent, sans risque), puis la facture. |
| `export_credit_note(credit_note)` | `PUT /api/v1/invoices/{ref}` avec `document_type: "credit_note"` | Sans lien vers une facture (cf. 6.3). |
| `reverse_invoice(invoice)` | `DELETE /api/v1/invoices/{ref}` | `reason` obligatoire : `invoice.cancellation_reason`, à défaut un texte fixe. Contrairement à Dolibarr, l'annulation est automatique. |
| `set_invoice_paid(invoice)` | aucun appel, **succès sans effet** | Le paiement se gère dans LedgerFlow et revient par le flux (section 9), jamais dans ce sens. Doit réussir : `Invoices::AccountingMarkAsPaidOrganizer` annule toute la transaction si l'adaptateur échoue, et marquer une facture payée dans BudgetFlow deviendrait impossible. Cf. 6.5. |
| `adapter_name` | `"LedgerFlow"` | |

Identifiants (`{ref}`), stables et déterministes : fournisseur `bf-supplier-{supplier.id}`, facture ou avoir `bf-invoice-{invoice.id}`. Une même référence ne peut pas passer de facture à avoir.

`Accounting::Result.external_id` : renvoyer l'`id` LedgerFlow de la réponse (chaîne). Il est stocké dans `accounting_external_id` ; l'`invoice_number` LedgerFlow (`ACH2026/0007`) peut aller dans `metadata`.

## 4. Correspondance des champs

### Fournisseur → `PUT /partners/{ref}`

| BudgetFlow (`Supplier`) | LedgerFlow | Remarque |
|---|---|---|
| `name` | `name` | obligatoire |
| — | `partner_type` | toujours `supplier` |
| `country_code`, à défaut `tin_country_code` | `country` | ISO 2 lettres |
| `tin_value` si `tin_type == "VAT"` | `vat_number` | BudgetFlow stocke déjà le préfixe pays pour les numéros de TVA (`BE0123456789`), ce que LedgerFlow exige. Tout autre identifiant fiscal (TPIN…) n'est **pas** envoyé. |
| `iban`, `bic`, `email` | `iban`, `bic`, `email` | IBAN contrôlé côté LedgerFlow |
| `peppol_id` | `peppol_participant_id` | |

Le rapprochement par numéro de TVA reprend un tiers LedgerFlow déjà saisi à la main (sans référence) au lieu de le dupliquer ; un numéro de TVA lié à une autre référence donne `409`.

### Facture → `PUT /invoices/{ref}`

| BudgetFlow (`Invoice`) | LedgerFlow | Remarque |
|---|---|---|
| — | `document_type` | `invoice` ou `credit_note` selon `invoice_type` |
| — | `post` | toujours `false` : la facture arrive en **brouillon**, le comptable la code et la comptabilise dans LedgerFlow |
| `effective_supplier` | `partner_external_ref` | `bf-supplier-{id}` |
| — | `invoice_type` | toujours `supplier` |
| `invoice_date`, `due_date` | `invoice_date`, `due_date` | ISO 8601 ; la date doit tomber dans un exercice **ouvert** |
| `currency` | `currency` | |
| `exchange_rate_used` (pas `effective_exchange_rate`, qui préfère le taux réel du paiement) | `exchange_rate` | **Inverser** (cf. 6.1). `"1.0"` pour l'EUR. |
| `project.id` | `project_id` | |
| `project.name` | `project_name` | affiché au comptable pour choisir les comptes analytiques |
| `invoice.sub_line` (via l'engagement) | `budget_line` | `"#{chapter.code}.#{budget_line.code}.#{sub_line.code}"` |
| `description` | `description` | |
| `invoice_lines` (ordre `position`) | `lines[]` | ci-dessous |
| `invoice_number` | — | Le numéro **du fournisseur** n'a pas de champ dédié côté LedgerFlow (cf. 6.2) |

Lignes :

| `InvoiceLine` | LedgerFlow `lines[]` |
|---|---|
| `description` | `description` |
| `quantity` | `quantity` (chaîne décimale) |
| `unit_price` (devise de la facture) | `unit_price` (chaîne décimale) |
| `vat_code.rate` | `vat_rate` |
| `accounting_account.number` | **non envoyé** : le comptable seul code les lignes dans LedgerFlow (elles arrivent sur le compte d'attente 499000 ; la comptabilisation est refusée tant qu'il en reste) |

Les montants sont envoyés en **chaînes décimales** (`"50.00"`) depuis des `BigDecimal`, jamais des `Float`. LedgerFlow recalcule les totaux et les grilles de TVA : ils ne s'envoient pas.

## 5. Statuts de réponse → `Accounting::Result`

| LedgerFlow | Adaptateur |
|---|---|
| `200`, `201` | `success(external_id: body["id"].to_s, …)` |
| `409` (`Concurrent update, retry`) | Réessayer (les `PUT` sont idempotents). |
| `409` (autre) | `failure` avec le motif : facture payée ou lettrée dans LedgerFlow, exercice clos, avoir comptabilisé… Ne pas réessayer ; à traiter par un humain. |
| `422` | `failure`, message = `errors` aplati (`lines[0].account_code: unknown account…`), stocké dans `accounting_export_error`. |
| `401`, `403` | `failure` de configuration (clé, scope). |
| `429` | `failure` « rate limit reached, retry in Ns » ; pas d'attente dans l'adaptateur, la relance revient au job d'export. |
| Réseau / timeout | `failure` ; le `PUT` peut être rejoué sans risque. |

## 6. Points d'attention (pièges relevés)

1. **Le taux de change est inversé.** BudgetFlow : `amount_eur = amount / exchange_rate_used` (devise étrangère pour 1 EUR, 8 décimales). LedgerFlow : `total_eur = total × exchange_rate` (EUR pour 1 unité de devise, **6 décimales**). L'adaptateur doit envoyer `1 / exchange_rate_used`. La perte de précision peut créer un écart de quelques centimes sur de gros montants en devise. Contrôle proposé : comparer `total_incl_vat` de la réponse à `invoice.amount` et signaler tout écart dans `accounting_export_error`. Décision à prendre : passer la colonne LedgerFlow à 8 décimales.
2. **Numéro de facture du fournisseur.** BudgetFlow a `invoice_number` (obligatoire, celui du fournisseur). LedgerFlow numérote lui-même (`ACH2026/…`) et n'a pas de champ dédié pour le numéro fournisseur dans l'API : `external_ref` est la clé BudgetFlow, pas ce numéro. Proposition : ajouter `supplier_reference` (colonne et champ d'API) et l'utiliser pour le contrôle de doublon R19 C05. **À décider** : en attendant, l'adaptateur peut le mettre dans `description`.
3. **Avoirs.** Un avoir BudgetFlow est une `Invoice` de type `credit_note` rattachée à un engagement, **sans lien vers la facture d'origine**. Il part donc sans `credited_invoice_external_ref`, ce que l'API accepte. Il réduit le solde du fournisseur mais n'est pas lettré contre une facture.
4. **Reçus (`invoice_type: receipt`).** Hors périmètre : ce ne sont pas des factures comptables. À ne pas exporter tant qu'il n'y a pas de règle.
5. **Statut de paiement.** Décision du 2026-09-29 : **LedgerFlow fait foi** (lettrage, rapprochement bancaire, lots SEPA) et BudgetFlow l'apprend par le flux d'événements (section 9). `set_invoice_paid` ne transmet rien mais **réussit** (sinon le paiement serait annulé dans BudgetFlow). Le statut à un instant donné reste lisible par `GET /api/v1/invoices/{ref}` (`status` : `posted`, `partially_paid`, `paid`, `cancelled`). Le bouton manuel « marquer payé » de BudgetFlow est **conservé** : voir les limites en section 9.
6. **Traitement de TVA.** L'adaptateur Dolibarr n'envoie aucun régime ; LedgerFlow applique alors `domestic`. Les achats intracommunautaires ou en autoliquidation demandent `vat_treatment` (`intracom_goods`, `intracom_services`, `construction_reverse_charge`, `export`, `exempt`) : BudgetFlow n'a pas cette information aujourd'hui.
7. **Corrections dans BudgetFlow** (`invoice_amount_corrections`, `invoice_reimputations`…) : renvoyer le même `PUT`. LedgerFlow crée une révision par extourne ; `409` si la facture est déjà payée ou lettrée là-bas. Une facture qui porte un avoir comptabilisé ne se révise pas : annuler l'avoir d'abord.
8. **Débit** : 300 requêtes par minute et par clé. Un export en masse doit espacer ses appels ou respecter `Retry-After`.

## 7. Code

Dans BudgetFlow : `app/services/accounting/ledgerflow/exporter.rb` (contrat `Accounting::Base`, plus `fetch_payment_events`) et `client.rb` (client `Net::HTTP`, en-tête `Authorization: Bearer <clé>`, erreurs `409`/`422` aplaties en message lisible, `429` avec `Retry-After`). Paiements : `payment_sync.rb`, `system_user.rb`, `app/services/invoices/mark_paid_from_ledgerflow_organizer.rb`, `app/jobs/ledgerflow_payment_sync_job.rb`, `AccountingMailer#payment_attention`.

Dans LedgerFlow : `Accounting::InvoiceEvent` (journal), point d'accroche `after_commit` du modèle `Accounting::Invoice`, `Api::V1::InvoiceEventsController`.

## 8. Tests

Côté BudgetFlow (`spec/services/accounting/ledgerflow/exporter_spec.rb`, `factory_spec`, `entity_setting_spec`), avec `Net::HTTP` simulé comme pour Dolibarr : contrat de chaque méthode de `Accounting::Base` (exemple partagé « an accounting exporter »), ordre fournisseur puis facture, corps et en-têtes envoyés, montants en chaînes décimales, taux de change inversé, avoir sans lien, tiers sans identifiant fiscal de type TVA, et chaque statut de réponse (409, 422 avec ligne nommée, 429, 401, réseau).

Synchronisation (`payment_sync_spec.rb`, `ledgerflow_payment_sync_job_spec.rb`, `accounting_mailer_spec.rb`) : paiement appliqué avec date, référence et acteur système ; reprise depuis le curseur sur plusieurs pages ; facture déjà payée à la main laissée telle quelle ; alerte pour une facture non payable ou un paiement annulé ; paiements partiels, références inconnues et autre entité ignorés ; panne de LedgerFlow sans avancer le curseur ; événement impossible à appliquer. Trois casses volontaires du code (paiement jamais appliqué, entité non vérifiée, curseur jamais stocké) font bien échouer la spec.

Côté LedgerFlow (`invoice_event_spec.rb`, `invoice_events_spec.rb`) : événements enregistrés pour toute transition de paiement, factures saisies à l'écran ignorées, flux à curseur, délai de sécurité, isolation entre entités, scopes.

Non testé côté BudgetFlow : l'idempotence, les révisions et les refus métier, qui sont le comportement de LedgerFlow (`spec/requests/api/v1/`). Une vérification croisée a été faite une fois, en envoyant les corps exacts de l'adaptateur à la vraie API. Elle n'est pas automatisée : si l'un des deux contrats change, la refaire.

## 9. Synchronisation des paiements (LedgerFlow → BudgetFlow)

Décision du 2026-09-29 : les paiements se gèrent dans LedgerFlow. BudgetFlow les apprend par **interrogation régulière** d'un flux d'événements plutôt que par webhook : aucune porte d'entrée nouvelle dans BudgetFlow, aucun événement perdu si BudgetFlow est éteint (le curseur le retient), LedgerFlow n'appelle toujours jamais BudgetFlow. Le flux est décrit dans `inbound-api.md` (4.4).

**Fonctionnement.** `LedgerflowPaymentSyncJob` (Solid Queue, toutes les 5 minutes, `config/recurring.yml`) parcourt les entités configurées sur `ledgerflow`. `Accounting::Ledgerflow::PaymentSync` lit `GET /api/v1/invoice_events?after=<curseur>` page par page ; le curseur est stocké par entité (`entity_settings.accounting_events_cursor`) et avancé événement par événement.

| Événement LedgerFlow | Effet dans BudgetFlow |
|---|---|
| `paid`, facture validée | Marquée payée par `Invoices::MarkPaidFromLedgerflowOrganizer` : sans pièce justificative ni comptable, `payment_method: "ledgerflow"`, `payment_status: "payment_manual"`, `payment_reference: "LedgerFlow <n°>"`, `paid_at` = `paid_on` à midi. |
| `paid`, facture déjà payée | Rien (pas d'alerte). |
| `paid`, facture dans un autre état (annulée…) | Rien de modifié ; e-mail aux comptables. |
| `payment_reopened`, facture encore payée | E-mail aux comptables : BudgetFlow n'a pas de transition « dépayer », ils corrigent par les corrections existantes. |
| `payment_reopened`, facture non payée ; `partially_paid` ; référence inconnue ou d'une autre entité | Ignoré (journalisé pour une référence inconnue). |

- **Acteur système** : `ledgerflow-sync@system.invalid`, utilisateur technique créé au premier besoin (le journal d'audit de BudgetFlow exige un utilisateur), mot de passe aléatoire que personne ne connaît, membre d'aucune entité ni d'aucun projet.
- **Alertes** : `AccountingMailer#payment_attention` aux comptables du projet, à défaut aux propriétaires et administrateurs de l'entité.
- **Robustesse** : si le flux ne peut pas être lu, le curseur reste en place et la tâche recommence 5 minutes plus tard ; un événement impossible à appliquer déclenche une alerte puis on passe, pour qu'un seul événement ne bloque pas le flux.
- **Montant** : `payment_amount_eur` reste vide. LedgerFlow ne fournit pas le montant réellement décaissé (écart de change), et BudgetFlow retombe alors sur `amount_eur`.

**Limites (à connaître).**
1. Le bouton manuel « marquer payé » de BudgetFlow est **conservé** (choix de l'utilisateur). Un paiement saisi à la main ne remonte pas vers LedgerFlow, et un événement `paid` sur une facture déjà payée à la main est ignoré : les deux sources peuvent diverger dans ce sens.
2. Les paiements partiels n'ont aucun effet dans BudgetFlow (pas d'état partiel).
3. Un paiement défait dans LedgerFlow n'est qu'une alerte : la facture reste payée dans BudgetFlow jusqu'à correction humaine.
4. BudgetFlow ne vérifie pas la révision d'un événement : la référence `bf-invoice-<id>` est stable d'une révision à l'autre.

## 10. Le comptable ne travaille que dans LedgerFlow (décision du 2026-09-30)

**Principe : séparer par rôle.** Le gestionnaire de projet reste dans BudgetFlow (encoder, pièces, engagement, approbation) ; le comptable ne fait **que** LedgerFlow (codage, analytique, comptabilisation, paiement, renvoi éventuel). Tout ce qui suit est opt-in : seules les entités LedgerFlow qui ont déclaré utiliser BudgetFlow, et les entités BudgetFlow dont l'adaptateur est `ledgerflow`, changent de comportement.

**Flux cible.** Le gestionnaire valide la facture (`validated`) → BudgetFlow l'envoie **automatiquement** en brouillon à LedgerFlow (`post: false`, sans comptes, avec `project_name` et `budget_line` = `chapitre.ligne.sous-ligne`) → elle apparaît dans la file « from BudgetFlow to process » de la liste des achats → le comptable code les lignes, choisit les comptes analytiques à partir du projet et de la ligne budgétaire, puis **comptabilise** ou **renvoie** au gestionnaire (motif obligatoire) → il met la facture en paiement → BudgetFlow reçoit l'état, le montant réellement payé, la date de valeur et la référence bancaire.

| Événement LedgerFlow | Ce que BudgetFlow en fait (cible) |
|---|---|
| `posted` | Facture « comptabilisée » : état `accounted`, numéro comptable visible. |
| `returned` (motif) | `return_to_draft` (acteur système, le motif devient le commentaire de rejet, le créateur et le circuit d'approbation sont prévenus), export remis à zéro ; après correction, nouvel envoi = révision suivante. |
| `paid` / `payment_confirmed` | Facture payée ; `payment_amount_eur` = montant réellement payé, `paid_at` = **date de valeur**, `payment_executed_at` = date d'opération, `payment_reference` = référence bancaire ; l'événement complet (liste des règlements, id, numéro comptable) est écrit dans le journal d'audit de BudgetFlow. Un `payment_confirmed` ultérieur met à jour ces faits. |
| `partially_paid` | Entrée du journal d'audit seulement (BudgetFlow n'a pas d'état partiel). |
| `payment_reopened` | Alerte aux comptables (BudgetFlow ne sait pas « dépayer »). |

**État d'avancement.**

- **LedgerFlow : fait (2026-09-30).** Entité qui déclare BudgetFlow et étanchéité de l'API et des écrans ; champs `post`, `project_name`, `budget_line`, lignes sans compte (compte d'attente `499000`, comptabilisation refusée tant qu'il en reste), brouillons corrigés en place ou refusés en `409` si le comptable y a travaillé, annulés sans extourne ; événements `posted`, `returned`, `payment_confirmed` et règlement détaillé ; bouton « Return to project manager » ; file de traitement (bandeau, filtre, pastille, contexte projet). Voir `inbound-api.md`.
- **BudgetFlow : fait (2026-09-30).** L'adaptateur envoie `post: false`, `project_name`, `budget_line` et aucun compte. Pour une entité `ledgerflow`, `Invoices::NotifyAccountantJob` (point unique appelé à la validation et après l'analyse IA) **exporte automatiquement** au lieu d'écrire au comptable ; le numéro fiscal du fournisseur et le journal BudgetFlow ne sont plus exigés ; un export en échec prévient le créateur et les administrateurs du projet (`AccountingMailer#export_failed`), pas un comptable ; le bouton d'export manuel ne reste que pour relancer un échec. `PaymentSync` traite `paid` et `payment_confirmed` (date de valeur → `paid_at`, date d'opération → `payment_executed_at`, référence bancaire → `payment_reference`, montant réellement payé → `payment_amount_eur`, événement complet dans le journal d'audit), `partially_paid` et `posted` (journal d'audit seulement), `returned` (retour en brouillon par l'acteur système, commentaire = motif, export remis à zéro) et `payment_reopened` (alerte).
- **Écart avec la décision initiale.** Il n'y a **pas** de nouvel état `accounted` : plusieurs règles de BudgetFlow (édition, export, paiement manuel) reposent sur `accounting_exported?`, et un état « hors exported » aurait réactivé l'export et bloqué le paiement manuel. La comptabilisation est donc consignée dans le journal d'audit (action `ledgerflow_posted`, avec le numéro comptable), la facture restant `exported`.
- **Vérification croisée (2026-09-30).** Les corps exacts de l'adaptateur ont été envoyés à la vraie API : brouillon non codé avec contexte, correction en place, comptabilisation refusée tant qu'une ligne est sur 499000, `posted`, `returned` (motif, puis révision 2 acceptée) et `paid` (date de valeur, référence bancaire, montant réel). Non automatisée : à refaire si un des deux contrats change.
- **À noter.** Une correction envoyée par BudgetFlow **après** la comptabilisation par le comptable crée une nouvelle révision en brouillon et extourne l'écriture (règle historique des révisions, `inbound-api.md` 4.1) : la comptabilité garde la trace, mais le comptable doit comptabiliser à nouveau. À discuter si BudgetFlow ne devrait pas pouvoir corriger une facture déjà comptabilisée.

## 11. Décisions ouvertes

1. ~~Accord pour écrire l'adaptateur dans BudgetFlow~~ : donné et réalisé.
2. Champ `supplier_reference` côté LedgerFlow (point 6.2).
3. Précision du taux de change LedgerFlow : 6 ou 8 décimales (point 6.1).
4. ~~Qui fait foi pour le statut de paiement~~ : LedgerFlow (2026-09-29). Reste ouvert : garder ou retirer le bouton manuel de BudgetFlow (limite 1 de la section 9).
5. Source du régime de TVA pour les achats hors Belgique (point 6.6).
6. R11 : BudgetFlow **pousse** ses budgets vers un endpoint entrant de LedgerFlow (`PUT /api/v1/budgets/{ref}`, même principe) plutôt que LedgerFlow ne les lise.

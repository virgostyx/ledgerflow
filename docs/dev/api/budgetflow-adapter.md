# Spécification : adaptateur `ledgerflow` pour BudgetFlow

Statut : **implémenté dans BudgetFlow** (2026-09-29, accord explicite de l'utilisateur) : `app/services/accounting/ledgerflow/{exporter,client}.rb` et ses specs, adaptateur `ledgerflow` déclaré dans `Accounting::Factory` et `EntitySetting`. Les corps JSON produits ont été vérifiés contre la vraie API de LedgerFlow (fournisseur, facture EUR et USD, avoir, annulation, rejeux). Ce document reste la référence du contrat.
Sources lues (lecture seule) : `budgetflow/app/services/accounting/` (`base.rb`, `factory.rb`, `dolibarr/exporter.rb`), `db/schema.rb`, `app/models/{invoice,entity_setting}.rb`.
Contrat côté LedgerFlow : `docs/dev/api/inbound-api.md`.

## 1. Idée

BudgetFlow exporte déjà ses factures vers un logiciel comptable par des **adaptateurs** qui implémentent `Accounting::Base`. LedgerFlow n'a pas besoin d'un client sortant : il suffit d'ajouter un adaptateur `ledgerflow` (à côté de `dolibarr`, `winbooks`, `null`) qui appelle l'API entrante de LedgerFlow. BudgetFlow reste maître de l'envoi ; LedgerFlow ne l'appelle jamais.

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
| `set_invoice_paid(invoice)` | aucun appel, **succès sans effet** | Doit réussir : `Invoices::AccountingMarkAsPaidOrganizer` annule toute la transaction si l'adaptateur échoue, et marquer une facture payée dans BudgetFlow deviendrait impossible. Cf. 6.5. |
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
| `effective_supplier` | `partner_external_ref` | `bf-supplier-{id}` |
| — | `invoice_type` | toujours `supplier` |
| `invoice_date`, `due_date` | `invoice_date`, `due_date` | ISO 8601 ; la date doit tomber dans un exercice **ouvert** |
| `currency` | `currency` | |
| `exchange_rate_used` (pas `effective_exchange_rate`, qui préfère le taux réel du paiement) | `exchange_rate` | **Inverser** (cf. 6.1). `"1.0"` pour l'EUR. |
| `project.id` | `project_id` | |
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
| `accounting_account.number` | `account_code` (compte PCMN, inconnu : `422` nommant la ligne) |

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
5. **Statut de paiement.** BudgetFlow suit le paiement de son côté (`payment_status`, `paid_at`) ; LedgerFlow le tire du rapprochement bancaire. `set_invoice_paid` ne transmet donc rien, mais **réussit** (sinon le paiement serait annulé dans BudgetFlow). Pour afficher le statut comptable dans BudgetFlow : `GET /api/v1/invoices/{ref}` (`status` : `posted`, `partially_paid`, `paid`, `cancelled`). **À décider** : qui fait foi si les deux divergent.
6. **Traitement de TVA.** L'adaptateur Dolibarr n'envoie aucun régime ; LedgerFlow applique alors `domestic`. Les achats intracommunautaires ou en autoliquidation demandent `vat_treatment` (`intracom_goods`, `intracom_services`, `construction_reverse_charge`, `export`, `exempt`) : BudgetFlow n'a pas cette information aujourd'hui.
7. **Corrections dans BudgetFlow** (`invoice_amount_corrections`, `invoice_reimputations`…) : renvoyer le même `PUT`. LedgerFlow crée une révision par extourne ; `409` si la facture est déjà payée ou lettrée là-bas. Une facture qui porte un avoir comptabilisé ne se révise pas : annuler l'avoir d'abord.
8. **Débit** : 300 requêtes par minute et par clé. Un export en masse doit espacer ses appels ou respecter `Retry-After`.

## 7. Code

Dans BudgetFlow : `app/services/accounting/ledgerflow/exporter.rb` (contrat `Accounting::Base`) et `client.rb` (client `Net::HTTP`, en-tête `Authorization: Bearer <clé>`, erreurs `409`/`422` aplaties en message lisible, `429` avec `Retry-After`).

## 8. Tests

Côté BudgetFlow (`spec/services/accounting/ledgerflow/exporter_spec.rb`, `factory_spec`, `entity_setting_spec`), avec `Net::HTTP` simulé comme pour Dolibarr : contrat de chaque méthode de `Accounting::Base` (exemple partagé « an accounting exporter »), ordre fournisseur puis facture, corps et en-têtes envoyés, montants en chaînes décimales, taux de change inversé, avoir sans lien, tiers sans identifiant fiscal de type TVA, et chaque statut de réponse (409, 422 avec ligne nommée, 429, 401, réseau).

Non testé côté BudgetFlow : l'idempotence, les révisions et les refus métier, qui sont le comportement de LedgerFlow (`spec/requests/api/v1/`). Une vérification croisée a été faite une fois, en envoyant les corps exacts de l'adaptateur à la vraie API. Elle n'est pas automatisée : si l'un des deux contrats change, la refaire.

## 9. Décisions ouvertes

1. ~~Accord pour écrire l'adaptateur dans BudgetFlow~~ : donné et réalisé.
2. Champ `supplier_reference` côté LedgerFlow (point 6.2).
3. Précision du taux de change LedgerFlow : 6 ou 8 décimales (point 6.1).
4. Qui fait foi pour le statut de paiement (point 6.5).
5. Source du régime de TVA pour les achats hors Belgique (point 6.6).
6. R11 : BudgetFlow **pousse** ses budgets vers un endpoint entrant de LedgerFlow (`PUT /api/v1/budgets/{ref}`, même principe) plutôt que LedgerFlow ne les lise.

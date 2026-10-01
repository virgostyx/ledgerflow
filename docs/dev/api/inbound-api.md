# API entrante : injecter de la comptabilité depuis une application tierce

Statut : implémentée (2026-09-29), complétée le 2026-09-30 (entités BudgetFlow, brouillons, règlements détaillés). Premier client : BudgetFlow.
Code : `app/controllers/api/v1/`, `app/services/accounting/external_invoice.rb`, `app/models/api_client.rb`.

## 1. Principes

- **Ce qu'on injecte** : des tiers (`partners`) puis des factures (`invoices`), jamais des écritures libres. Les écritures naissent de la facture par les services habituels (numérotation, TVA, comptabilisation).
- **Clé d'identification** : la référence de l'appelant, `external_ref`, unique par entité (et par révision pour les factures).
- **Idempotent** : renvoyer le même contenu ne change rien. Aucun en-tête `Idempotency-Key` n'est utilisé : c'est `external_ref` + le contenu qui font foi.
- **Corriger, jamais réécrire** : une facture comptabilisée n'est pas modifiée. Une modification annule l'ancienne pièce par extourne et comptabilise une nouvelle **révision** sous la même référence (cf. chaîne de hachage R18).
- **Montants** : `numeric(15,2)` en base, `BigDecimal` côté LedgerFlow. Envoyer des **chaînes décimales** (`"50.00"`). Les nombres JSON sont acceptés mais passent par leur écriture décimale, jamais par un flottant.
- **Tout ou rien** : une création ou une révision qui échoue ne laisse aucune trace comptable.

## 2. Authentification et autorisation

**L'API n'existe que pour les entités qui ont déclaré utiliser BudgetFlow** (case « This entity uses BudgetFlow » à la création de l'entité, modifiable par son administrateur dans ses réglages). Pour toute autre entité, l'écran « API Clients » n'existe pas, aucun client ne peut être créé, et tout appel (clé ou JWT) reçoit `403 {"error":"The BudgetFlow integration is not enabled for this entity"}`. Il en va de même pour tout ce que décrit ce document côté interface (file de traitement, renvoi au gestionnaire) : une entité non activée n'en voit rien.

Chaque application est un **client API** créé par un administrateur dans *Settings → API Clients* : nom, permissions (scopes), clé `lf_…` affichée **une seule fois** (stockée sous forme de hash SHA-256). La clé peut être renouvelée (l'ancienne cesse de fonctionner aussitôt) ou révoquée (définitif).

```
Authorization: Bearer lf_xxxxxxxxxxxxxxxxxxxxxxxx
Content-Type: application/json
```

- L'**entité comptable** est celle du client. Elle ne se choisit jamais dans la requête.
- Scopes : `partners:write`, `invoices:write`, `invoices:read`.
- Une action sans scope déclaré est refusée (fermé par défaut).
- Chaque appel est journalisé dans `api_requests` (méthode, chemin, statut, durée, `external_ref`) et met à jour la date de dernier usage.

| Cas | Réponse |
|---|---|
| Clé absente, inconnue ou révoquée | `401 {"error":"Unauthorized"}` |
| Scope manquant | `403 {"error":"Forbidden","required_scope":"invoices:write"}` |

### Limitation de débit

300 requêtes par minute **par clé** et 300 par minute **par IP** sur `/api/` (Rack::Attack, `config/initializers/rack_attack.rb`). Au-delà, la réponse est :

```
HTTP/1.1 429 Too Many Requests
Retry-After: 23
{"error":"Too Many Requests","retry_after":23}
```

`Retry-After` donne les secondes restantes avant la fin de la fenêtre. Une requête refusée n'atteint pas l'application (ni authentification, ni journal `api_requests`). Une synchronisation en masse doit rester sous 5 requêtes par seconde ou respecter `Retry-After`.

Le JWT historique (secret partagé) reste accepté, avec accès complet et sans journal `api_requests`. Il est **déprécié** : ne pas l'utiliser pour de nouvelles intégrations.

### Contrôle de connexion : `GET /api/v1/ping`

Accessible à tout client actif, **sans scope** requis. Sert de `health_check` à une application tierce.

```json
{ "status": "ok", "entity": "Ma Fondation ASBL", "api_client": "BudgetFlow",
  "scopes": ["invoices:read", "invoices:write", "partners:write"], "time": "2026-09-29T10:15:00Z" }
```

`401` si la clé est absente, inconnue ou révoquée. Un client peut ainsi vérifier qu'il dispose bien de tous les scopes dont il a besoin.

## 3. Tiers : `PUT /api/v1/partners/:external_ref` (scope `partners:write`)

À appeler à la création (et à chaque modification) d'un tiers dans l'application tierce, **avant** d'envoyer une facture qui le référence.

```json
{
  "name": "ACME SPRL",
  "partner_type": "supplier",
  "vat_number": "BE0123456789",
  "country": "BE",
  "iban": "BE68539007547034",
  "email": "compta@acme.be",
  "payment_terms_days": 30
}
```

Champs : `name` (obligatoire), `partner_type` (`customer` | `supplier` | `both`), `vat_number` (préfixe pays + format national contrôlés), `email`, `phone`, `street`, `city`, `zip`, `country` (ISO, `BE` par défaut), `iban` (contrôlé), `bic`, `payment_terms_days`, `peppol_participant_id`, `active`, `notes`.

- Référence inconnue → création. Sinon mise à jour des champs envoyés.
- **Rapprochement par TVA** : si la référence est inconnue mais qu'un tiers existant **sans référence** porte le même numéro de TVA, il est repris (pas de doublon).
- Un numéro de TVA déjà lié à **une autre** référence donne `409`.
- Les modifications sont auditées (R18), avec le nom du client API.

| Statut | Signification |
|---|---|
| `201` | Tiers créé |
| `200` | Tiers mis à jour, ou rejeu identique |
| `409 {"error":"VAT number belongs to another external_ref"}` | Conflit de rapprochement |
| `409 {"error":"Concurrent update, retry"}` | Deux envois simultanés : rejouer |
| `422 {"errors":{"vat_number":["is invalid"],…}}` | Validation, détail par champ |

Corps de réponse : `{id, external_ref, name, partner_type, vat_number, country, active}`.

## 4. Factures

### 4.1 Créer, réviser : `PUT /api/v1/invoices/:external_ref` (scope `invoices:write`)

```json
{
  "partner_external_ref": "BF-P-1",
  "invoice_type": "supplier",
  "invoice_date": "2026-09-29",
  "due_date": "2026-10-29",
  "currency": "EUR",
  "vat_treatment": "domestic",
  "description": "Mission de conseil",
  "project_id": 7,
  "lines": [
    { "account_code": "604000", "description": "Consulting", "quantity": "2", "unit_price": "50.00", "vat_rate": "21" }
  ]
}
```

| Champ | Règle |
|---|---|
| `partner_external_ref` | Obligatoire. Doit avoir été envoyé via `PUT /partners` (sinon `422`, aucune création implicite). |
| `document_type` | `invoice` (défaut) ou `credit_note` (cf. 4.5). |
| `credited_invoice_external_ref` | Avoir seulement : référence de la facture créditée (facultatif). |
| `post` | `true` par défaut : la facture est comptabilisée tout de suite. **`false` : elle reste un brouillon** que le comptable code et comptabilise dans LedgerFlow (mode de BudgetFlow). |
| `supplier_reference` | Facultatif. Numéro de la facture **chez le fournisseur** (pour BudgetFlow : `invoice_number`). Distinct de `external_ref`, qui est la clé de l'appelant. Fait partie du contenu. |
| `project_name`, `budget_line` | Facultatifs. Nom du projet et ligne budgétaire `chapitre.ligne.sous-ligne`, affichés au comptable pour choisir les comptes analytiques. Font partie du contenu (les changer est une correction). |
| `invoice_type` | Obligatoire : `supplier` ou `customer`. |
| `invoice_date` | Obligatoire, ISO 8601. Doit tomber dans un **exercice ouvert**. |
| `due_date`, `description`, `notes`, `project_id` | Facultatifs. `project_id` est l'identifiant BudgetFlow, sans clé étrangère. |
| `currency`, `exchange_rate` | `EUR` et `1` par défaut. |
| `vat_treatment` | `domestic` (défaut), `intracom_goods`, `intracom_services`, `construction_reverse_charge`, `export`, `exempt`. |
| `lines[]` | Au moins une. L'ordre du tableau donne la position. |
| `lines[].account_code` | **Code de compte PCMN** (ex. `604000`). **Facultatif** : une ligne sans code va sur le compte d'attente `499000` (le comptable la code), et la facture ne peut pas être comptabilisée tant qu'une ligne y reste (`422` si `post: true`). Code inconnu : `422` nommant la ligne. Si le plan comptable n'a pas de compte `499000` : `422`. |
| `lines[].quantity`, `unit_price`, `vat_rate` | Décimaux. `vat_rate` en pourcentage. |

Les grilles TVA et les comptes de TVA ne sont **pas** envoyés : LedgerFlow les déduit (préfixe du compte de charge pour un achat, taux pour une vente), comme pour une facture saisie à l'écran. Les règles de franchise de TVA de l'entité s'appliquent.

**Comportement** (le contenu est normalisé puis comparé par empreinte : `0.1` et `"0.10"` sont identiques) :

| Situation | Effet | Statut |
|---|---|---|
| Référence inconnue | Facture créée et comptabilisée, révision 1 | `201` |
| Même contenu que la révision en cours | Rien | `200` |
| Contenu différent | Révision en cours annulée par extourne, révision n+1 comptabilisée | `200` |
| Révision en cours déjà annulée (par `DELETE`) | Nouvelle révision comptabilisée | `201` |

**Brouillons** (`post: false`) :

| Situation | Effet | Statut |
|---|---|---|
| Référence inconnue | Brouillon créé (pas d'écriture, pas de numéro, totaux calculés) | `201` |
| Même contenu | Rien | `200` |
| Contenu différent, brouillon **intact** | Brouillon remplacé en place (même document, même révision) | `200` |
| Contenu différent, **le comptable y a travaillé** (lignes, comptes, annotations analytiques modifiés) | Refusé : `409` « The accountant is already processing this draft: ask for it to be returned first. » | `409` |
| `DELETE` | Brouillon annulé, sans extourne (il n'y a pas d'écriture) | `200` |
| Facture **déjà comptabilisée** par le comptable, contenu différent | Refusé : `409` « Already booked in LedgerFlow: the accountant must return it to the project manager from LedgerFlow. » Les livres appartiennent au comptable ; après son renvoi depuis LedgerFlow, un nouvel envoi crée une révision en brouillon. | `409` |
| Brouillon renvoyé ou annulé, puis nouvel envoi | Nouvelle révision | `201` |

Cette règle vaut pour le **mode brouillon** (`post: false`). Un client qui comptabilise d'office (`post` absent ou `true`) garde la révision par extourne décrite plus haut. Un renvoi identique au contenu d'origine reste un `200` même si le comptable a déjà travaillé sur le brouillon : un rejeu n'est pas une correction. `post: true` sur un brouillon intact le remplace et le comptabilise.

Envois simultanés pour une même référence : l'index unique garantit un seul gagnant, l'autre reçoit `409 {"errors":{"base":["Concurrent update, retry"]}}` sans rien avoir écrit ; il suffit de rejouer.

Refus de révision (`409`, rien n'est modifié) : la révision en cours est payée ou partiellement payée, lettrée, dans un lot de paiement actif, déjà créditée, liée à une immobilisation, ou son exercice est clos. Corps : `{"errors":{"base":["<motif>"]}}`.

Si c'est la **nouvelle** révision qui ne peut pas être comptabilisée (par exemple une déclaration TVA déjà déposée sur la période), la réponse est `422 {"errors":{"base":["<motif>"]}}` et l'extourne est annulée avec le reste : l'ancienne révision reste en vigueur.

Corps de réponse :

```json
{ "id": 812, "external_ref": "BF-I-1", "revision": 2, "invoice_number": "ACH2026/0007",
  "status": "posted", "invoice_date": "2026-09-29", "total_incl_vat": "145.2", "partner_id": 3 }
```

### 4.2 Annuler : `DELETE /api/v1/invoices/:external_ref` (scope `invoices:write`)

Corps ou paramètre `reason` **obligatoire** : le motif est enregistré dans la piste d'audit avec le nom du client API.

| Statut | Signification |
|---|---|
| `200` | Brouillon annulé (sans extourne), facture comptabilisée d'office annulée (extourne), ou déjà annulée (rejeu) |
| `409 « Already booked in LedgerFlow: the accountant must return it to the project manager from LedgerFlow. »` | Document remis en mode brouillon (`post: false`) puis **comptabilisé** par le comptable : l'appelant ne peut ni le corriger ni le supprimer. Le comptable le renvoie depuis LedgerFlow (« Return to project manager » : écriture extournée, événement `returned` avec le motif), puis un nouvel envoi crée une révision en brouillon. |
| `404 {"errors":{"base":["Unknown external_ref"]}}` | Référence inconnue |
| `409` | Facture comptabilisée d'office payée, lettrée, en lot de paiement, créditée ou liée à une immobilisation : défaire d'abord côté LedgerFlow |
| `422 {"errors":{"reason":["is required"]}}` | Motif absent |

### 4.3 Consulter : `GET /api/v1/invoices/:external_ref` (scope `invoices:read`)

Renvoie la **révision courante** et l'historique, pour connaître à tout moment le statut comptable d'une facture. Pour être informé des paiements sans interroger chaque facture, utiliser le flux d'événements (4.4).

```json
{ "id": 812, "external_ref": "BF-I-1", "revision": 2, "status": "posted", "invoice_number": "ACH2026/0007",
  "invoice_date": "2026-09-29", "total_incl_vat": "145.2", "partner_id": 3,
  "revisions": [ { "revision": 1, "status": "cancelled", "invoice_number": "ACH2026/0006" },
                 { "revision": 2, "status": "posted",    "invoice_number": "ACH2026/0007" } ] }
```

Statuts : `draft`, `posted`, `partially_paid`, `paid`, `cancelled`. Référence inconnue : `404 {"error":"Not found"}`.

`GET /api/v1/invoices?status=posted` (scope `invoices:read`) liste toutes les factures de l'entité, y compris celles saisies à l'écran.

### 4.4 Événements de paiement : `GET /api/v1/invoice_events` (scope `invoices:read`)

Les paiements se gèrent dans LedgerFlow (lettrage, rapprochement bancaire, lots SEPA) ; l'application tierce **interroge ce flux** pour les apprendre, par exemple toutes les 5 minutes. Le flux est un journal en ajout seul, limité aux factures et avoirs **gérés par l'API**, et à l'entité du client.

`GET /api/v1/invoice_events?after=<dernier id traité>&limit=100` (`limit` : 100 par défaut, 500 au plus) :

```json
{ "events": [
    { "id": 42, "type": "paid", "occurred_at": "2026-09-29T10:15:00Z", "external_ref": "bf-invoice-10", "revision": 1,
      "invoice_number": "ACH2026/0007", "currency": "EUR", "total_incl_vat": "121.0", "amount_eur": "121.0", "paid_on": "2026-09-25" } ],
  "next_cursor": 42 }
```

| `type` | Quand | Champs propres |
|---|---|---|
| `received` | Une facture Peppol vient d'arriver dans LedgerFlow (entités qui utilisent BudgetFlow seulement ; pas pour les avoirs). Charge : `lf_id` (à utiliser pour la reprise), `supplier_reference`, `supplier` (`name`, `vat_number`), `invoice_date`, `due_date`, `currency`, `amount_excl_vat`, `vat_amount`, `total_incl_vat`, `order_reference`, `buyer_reference`, `has_pdf`. Pas de `external_ref` : la facture n'est pas encore reprise. | voir 4.7 |
| `posted` | Le comptable a comptabilisé un brouillon (pas émis quand l'API comptabilise à la création : la réponse le dit déjà) | `invoice_number` |
| `paid` | La ligne fournisseur/client de la facture est entièrement réglée | règlement (ci-dessous) |
| `partially_paid` | Règlement partiel | règlement à ce jour |
| `payment_confirmed` | Le débit bancaire d'un paiement déjà fait (lot SEPA) vient d'être rapproché : on apprend la date de valeur et la référence réelles | règlement complet, avec les faits bancaires |
| `payment_reopened` | Un règlement est défait (délettrage, allocation retirée) | aucun montant |
| `returned` | Le comptable a renvoyé le brouillon au gestionnaire | `reason` (obligatoire) |

**Règlement** (`paid`, `partially_paid`, `payment_confirmed`) : pour l'auditeur, un détail par paiement et des totaux :

```json
{ "amount_eur": "121.0", "paid_on": "2026-09-28", "reference": "E2E-REF-1",
  "settlements": [ { "value_date": "2026-09-28", "transaction_date": "2026-09-27", "reference": "E2E-REF-1",
      "description": "Payment ACME", "amount": "121.0", "currency": "EUR", "amount_eur": "121.0",
      "shared": false, "source": "bank_transaction" } ] }
```

`value_date` = date de valeur du mouvement bancaire, `transaction_date` = date d'opération, `reference` = référence bancaire, `amount`/`currency` = le mouvement entier, `amount_eur` = **part réellement payée pour cette facture**, `shared: true` quand un virement règle plusieurs factures. `source` dit d'où vient l'information : `bank_transaction` (mouvement bancaire rapproché), `payment_batch` (lot SEPA exécuté, banque pas encore rapprochée : référence du lot), `journal_entry` (écriture de paiement sans mouvement importé, par exemple un compte à l'étranger), `transition` (rien d'autre n'est connu : la ligne entière, à la date de l'événement). Les totaux : `amount_eur` = somme des parts (montant EUR réellement décaissé, y compris l'écart de change), `fx_difference_eur` = résultat de change réalisé comptabilisé au lettrage (positif = gain, négatif = perte, `0.0` pour une facture en EUR), `paid_on` = dernière date de valeur, `reference` = celle du dernier règlement.

- **Curseur** : renvoyer `next_cursor` en `after` à l'appel suivant. Une page vide renvoie l'`after` reçu. Les événements sont **immuables** : un règlement défait ajoute un événement `payment_reopened`, il n'efface rien.
- **Délai de sécurité** : un événement n'apparaît qu'au bout de 5 secondes, pour qu'une transaction encore ouverte ne publie pas un id inférieur à un curseur déjà avancé.
- **Idempotence** : traiter deux fois le même `id` doit rester sans effet côté appelant.
- **Lot SEPA** : la facture passe à « payée » à l'exécution du lot, avant la banque. Le premier événement (`paid`) porte alors la référence du lot (`source: payment_batch`) ; le rapprochement du débit bancaire ajoute un `payment_confirmed` avec la date de valeur et la référence réelles. L'appelant doit traiter les deux.
- **Devises** : `amount_eur` est ce qui a été imputé à la facture dans le règlement ; l'écart de change est donné à part dans `fx_difference_eur`. Pour un compte en devise étrangère, `amount`/`currency` = le mouvement dans la devise du compte, `amount_eur` = l'équivalent EUR saisi par le comptable (« Pay a supplier invoice »). Voir `docs/dev/audit-foreign-bank-accounts.md`.
- **Le sens inverse n'existe pas** : un paiement saisi dans l'application tierce ne remonte pas vers LedgerFlow.

### 4.5 Avoirs (notes de crédit)

Un avoir est envoyé sur le **même endpoint**, avec `document_type: "credit_note"`. Il hérite de tout ce qui précède : idempotence, révisions par extourne, `DELETE` avec motif, `GET`. Les lignes portent des montants **positifs**, comme une facture.

```json
{ "document_type": "credit_note", "credited_invoice_external_ref": "BF-I-1",
  "partner_external_ref": "BF-P-1", "invoice_type": "supplier", "invoice_date": "2026-09-30",
  "lines": [ { "account_code": "604000", "description": "Remboursement", "quantity": "1", "unit_price": "50.00", "vat_rate": "21" } ] }
```

- **Lien facultatif** : sans `credited_invoice_external_ref`, l'avoir est comptabilisé seul. Avec lien, la facture créditée doit être une facture API **en vigueur** (ni annulée, ni un avoir) et l'avoir doit avoir les mêmes tiers, type de facture et traitement de TVA : sinon `422` (`credited_invoice_external_ref` ou `credited_invoice`).
- **Plafond** : le cumul des avoirs comptabilisés ne peut pas dépasser le total de la facture (`422`, rien n'est écrit).
- **Effet immédiat** : un avoir comptabilisé réduit aussitôt le solde restant de la facture créditée. Le **lettrage** de l'avoir contre la facture reste une action comptable manuelle dans LedgerFlow, l'API ne le fait pas.
- **Une référence, un type** : une même `external_ref` ne peut pas passer de facture à avoir (ni l'inverse) : `422` sur `document_type`. Les références d'avoirs et de factures partagent le même espace de noms.
- **Ordre des corrections** : une facture qui porte un avoir comptabilisé ne peut être ni révisée ni annulée (`409`). Annuler d'abord l'avoir (`DELETE`), corriger la facture, puis renvoyer l'avoir.
- `GET` et les réponses d'écriture ajoutent `document_type` et, pour un avoir lié, `credited_invoice_external_ref`.

### 4.6 Erreurs de validation

`422` avec le détail par champ ; les lignes sont nommées par leur rang :

```json
{ "errors": { "partner_external_ref": ["unknown partner, send it first via PUT /api/v1/partners/:external_ref"],
              "lines[0].account_code": ["unknown account \"999999\""],
              "lines": ["at least one line is required"] } }
```

Un exercice non ouvert à la date de facture donne `409` (`errors.invoice_date`) plutôt que `422` : c'est un état de la comptabilité, pas une erreur de saisie.

### 4.7 Reprendre une facture Peppol reçue

Une facture reçue par Peppol est annoncée par l'événement `received` (4.4). Le gestionnaire de projet la rattache à un engagement dans l'application tierce ; celle-ci la **reprend** pour que son export (`PUT /invoices/:external_ref`) remplisse ce même brouillon au lieu d'en créer un second.

- `GET /api/v1/incoming_invoices/:id/documents/pdf` et `.../documents/xml` (scope `invoices:read`) : le PDF que le fournisseur a embarqué (dans le navigateur) et le XML UBL d'origine. `404` si l'id est inconnu, si la facture n'est pas une facture Peppol reçue, ou si le document n'existe pas. `:id` est le `lf_id` de l'événement.
- `POST /api/v1/incoming_invoices/:id/claim` (scope `invoices:write`), corps `{"external_ref": "bf-invoice-10"}` : le brouillon devient le document que l'appelant adresse par cette référence (révision 1, toujours un brouillon, documents conservés). Le numéro du fournisseur reste dans `supplier_reference`. Réponse `200 {id, external_ref, status, supplier_reference, order_reference, buyer_reference}`.

| Statut | Cas |
|---|---|
| `200` | Reprise faite, ou rejeu avec la même référence |
| `404` | Facture inconnue ou non reçue par Peppol |
| `409` | Déjà reprise sous une autre référence ; plus un brouillon (le comptable l'a comptabilisée ou annulée) ; référence déjà utilisée par un autre document |
| `422` | `external_ref` absent |

Ensuite, le `PUT /invoices/:external_ref` d'export suit la règle des brouillons (4.1) : remplacement en place si le comptable n'y a pas touché depuis la reprise, sinon `409` (le comptable la renvoie alors avec « Return to project manager »). Les lignes envoyées remplacent les lignes éventuelles ; la référence de commande, la référence acheteur et les documents restent.

## 5. Isolation entre pièces tierces et pièces saisies

Seules les factures **gérées par l'API** (identifiées par leur empreinte de contenu) sont adressables par `external_ref`. Le champ libre `external_ref` d'une facture saisie à l'écran (souvent le numéro du fournisseur, non unique) n'est jamais lu, repris ni annulé par l'API. L'unicité `(entité, external_ref, révision)` ne porte que sur les pièces de l'API.

## 6. Piste d'audit (R18)

Toute écriture née d'un appel API porte dans la chaîne de hachage : IP, agent, `request_id` et `{"api_client": {"id", "name"}}`. Les tiers sont audités champ par champ. Le motif d'une annulation ou d'une révision figure sur la ligne d'extourne (`Revised by BudgetFlow (revision 2)` pour une révision).

## 7. Exemple

```bash
curl -X PUT https://ledgerflow.example/api/v1/invoices/BF-I-1 \
  -H "Authorization: Bearer $LF_KEY" -H "Content-Type: application/json" \
  -d '{"partner_external_ref":"BF-P-1","invoice_type":"supplier","invoice_date":"2026-09-29",
       "lines":[{"account_code":"604000","description":"Consulting","quantity":"2","unit_price":"50.00","vat_rate":"21"}]}'
```

## 8. Limites connues et reporté

- **Limitation de débit** : compteurs en mémoire du processus (Rack::Attack). Suffisant tant que le déploiement reste mono-processus (`WEB_CONCURRENCY: 1`) ; avec plusieurs processus, passer le magasin de `config/initializers/rack_attack.rb` sur un cache partagé (Solid Cache).
- **Pas de choix du journal** via l'API : le journal suit le type de facture. Pas de lettrage automatique d'un avoir.
- **Pas de suppression de tiers** par l'API (désactiver via `active: false`).
- **Pas de webhook** : LedgerFlow n'appelle jamais l'application tierce ; elle interroge `GET /api/v1/invoice_events`. Un webhook qui réveillerait l'interrogation reste possible plus tard.
- **Lots asynchrones** et écritures libres : volontairement absents.
- **Comptes bancaires à l'étranger** : audités (`docs/dev/audit-foreign-bank-accounts.md`). Mouvement saisi à la main ou importé, paiement manuel d'une facture avec écart de change ; pas de paiement partiel manuel ni de réévaluation de clôture.
- **Analytique** : le comptable choisit les comptes analytiques à la main à partir de `project_name` et `budget_line` ; aucun pré-remplissage automatique.
- **PDF de la facture** : LedgerFlow ne le conserve pas (la copie d'audit reste dans l'application tierce).
- `POST /api/v1/journal_entries` a été **supprimé** ; `GET /api/v1/journal_entries` (lecture) reste.
- Le budget vs réalisé (R11) est un sujet distinct : il suppose que BudgetFlow pousse ses budgets vers LedgerFlow (cf. `budgetflow-adapter.md`), non traité ici.

# API entrante : injecter de la comptabilité depuis une application tierce

Statut : implémentée (2026-09-29). Premier client prévu : BudgetFlow.
Code : `app/controllers/api/v1/`, `app/services/accounting/external_invoice.rb`, `app/models/api_client.rb`.

## 1. Principes

- **Ce qu'on injecte** : des tiers (`partners`) puis des factures (`invoices`), jamais des écritures libres. Les écritures naissent de la facture par les services habituels (numérotation, TVA, comptabilisation).
- **Clé d'identification** : la référence de l'appelant, `external_ref`, unique par entité (et par révision pour les factures).
- **Idempotent** : renvoyer le même contenu ne change rien. Aucun en-tête `Idempotency-Key` n'est utilisé : c'est `external_ref` + le contenu qui font foi.
- **Corriger, jamais réécrire** : une facture comptabilisée n'est pas modifiée. Une modification annule l'ancienne pièce par extourne et comptabilise une nouvelle **révision** sous la même référence (cf. chaîne de hachage R18).
- **Montants** : `numeric(15,2)` en base, `BigDecimal` côté LedgerFlow. Envoyer des **chaînes décimales** (`"50.00"`). Les nombres JSON sont acceptés mais passent par leur écriture décimale, jamais par un flottant.
- **Tout ou rien** : une création ou une révision qui échoue ne laisse aucune trace comptable.

## 2. Authentification et autorisation

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

Le JWT historique (secret partagé) reste accepté, avec accès complet et sans journal `api_requests`. Il est **déprécié** : ne pas l'utiliser pour de nouvelles intégrations.

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
| `invoice_type` | Obligatoire : `supplier` ou `customer`. |
| `invoice_date` | Obligatoire, ISO 8601. Doit tomber dans un **exercice ouvert**. |
| `due_date`, `description`, `notes`, `project_id` | Facultatifs. `project_id` est l'identifiant BudgetFlow, sans clé étrangère. |
| `currency`, `exchange_rate` | `EUR` et `1` par défaut. |
| `vat_treatment` | `domestic` (défaut), `intracom_goods`, `intracom_services`, `construction_reverse_charge`, `export`, `exempt`. |
| `lines[]` | Au moins une. L'ordre du tableau donne la position. |
| `lines[].account_code` | **Code de compte PCMN** (ex. `604000`), obligatoire. Inconnu : `422` nommant la ligne. |
| `lines[].quantity`, `unit_price`, `vat_rate` | Décimaux. `vat_rate` en pourcentage. |

Les grilles TVA et les comptes de TVA ne sont **pas** envoyés : LedgerFlow les déduit (préfixe du compte de charge pour un achat, taux pour une vente), comme pour une facture saisie à l'écran. Les règles de franchise de TVA de l'entité s'appliquent.

**Comportement** (le contenu est normalisé puis comparé par empreinte : `0.1` et `"0.10"` sont identiques) :

| Situation | Effet | Statut |
|---|---|---|
| Référence inconnue | Facture créée et comptabilisée, révision 1 | `201` |
| Même contenu que la révision en cours | Rien | `200` |
| Contenu différent | Révision en cours annulée par extourne, révision n+1 comptabilisée | `200` |
| Révision en cours déjà annulée (par `DELETE`) | Nouvelle révision comptabilisée | `201` |

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
| `200` | Facture annulée (extourne comptabilisée), ou déjà annulée (rejeu) |
| `404 {"errors":{"base":["Unknown external_ref"]}}` | Référence inconnue |
| `409` | Facture payée, lettrée, en lot de paiement, créditée ou liée à une immobilisation : défaire d'abord côté LedgerFlow |
| `422 {"errors":{"reason":["is required"]}}` | Motif absent |

### 4.3 Consulter : `GET /api/v1/invoices/:external_ref` (scope `invoices:read`)

Renvoie la **révision courante** et l'historique, pour connaître le statut comptable sans client sortant.

```json
{ "id": 812, "external_ref": "BF-I-1", "revision": 2, "status": "posted", "invoice_number": "ACH2026/0007",
  "invoice_date": "2026-09-29", "total_incl_vat": "145.2", "partner_id": 3,
  "revisions": [ { "revision": 1, "status": "cancelled", "invoice_number": "ACH2026/0006" },
                 { "revision": 2, "status": "posted",    "invoice_number": "ACH2026/0007" } ] }
```

Statuts : `draft`, `posted`, `partially_paid`, `paid`, `cancelled`. Référence inconnue : `404 {"error":"Not found"}`.

`GET /api/v1/invoices?status=posted` (scope `invoices:read`) liste toutes les factures de l'entité, y compris celles saisies à l'écran.

### 4.4 Erreurs de validation

`422` avec le détail par champ ; les lignes sont nommées par leur rang :

```json
{ "errors": { "partner_external_ref": ["unknown partner, send it first via PUT /api/v1/partners/:external_ref"],
              "lines[0].account_code": ["unknown account \"999999\""],
              "lines": ["at least one line is required"] } }
```

Un exercice non ouvert à la date de facture donne `409` (`errors.invoice_date`) plutôt que `422` : c'est un état de la comptabilité, pas une erreur de saisie.

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

- **Pas de limitation de débit** : prévue au plan, non implémentée.
- **Pas d'avoir (note de crédit)** ni de choix du journal via l'API : le journal suit le type de facture.
- **Pas de suppression de tiers** par l'API (désactiver via `active: false`).
- **LedgerFlow ne notifie pas l'appelant** : il doit interroger `GET`. Un client sortant / webhook reste à concevoir.
- **Lots asynchrones** et écritures libres : volontairement absents.
- `POST /api/v1/journal_entries` a été **supprimé** ; `GET /api/v1/journal_entries` (lecture) reste.
- Le budget vs réalisé (R11) est un sujet distinct : il suppose un client sortant vers BudgetFlow, non traité ici.

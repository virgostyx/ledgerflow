# Test réel BudgetFlow ↔ LedgerFlow : projet PRODEM ZAMBIA (évaluation du 2026-10-21)

Objectif : faire comptabiliser dans LedgerFlow les factures 2026 du projet PRODEM ZAMBIA de BudgetFlow, et valider le lien dans tous ses détails (envoi, correction, renvoi, paiement, retour).
Sources lues (lecture seule) : `budgetflow/app/services/accounting/ledgerflow/*`, `Invoices::NotifyAccountantJob`, `AccountingExportJob`, `ledgerflow/docs/dev/api/{inbound-api,budgetflow-adapter}.md`, `Accounting::ExternalInvoice`, `Fx::Convert`.
Rien n'a été modifié dans BudgetFlow.

## 1. Verdict

**Faisable, mais pas tel quel.** Un défaut bloquant côté BudgetFlow (§2), trois décisions comptables à prendre avant de comptabiliser quoi que ce soit (§3), et un cadre de test à choisir pour ne pas polluer la production (§5).

## 2. Défaut bloquant : le taux de change est encore inversé (BudgetFlow)

- `Accounting::Ledgerflow::Exporter#exchange_rate` (BudgetFlow) renvoie `1 / exchange_rate_used`, avec le commentaire « BudgetFlow divides, LedgerFlow multiplies ».
- Depuis F11, LedgerFlow utilise **la même convention** que BudgetFlow : taux = unités de devise pour 1 EUR, `EUR = montant ÷ taux` (`Fx::Convert.to_eur`). `inbound-api.md` le dit : « il n'y a plus rien à inverser ».
- Conséquence : une facture USD à 1,08 part avec 0,926 ; LedgerFlow calcule `montant ÷ 0,926`, soit `montant × 1,08` au lieu de `montant ÷ 1,08`. L'erreur est de facteur `taux²` (≈ 17 % sur l'USD, énorme sur le kwacha). Toute facture en devise est fausse en euros.
- Le test de BudgetFlow (`exporter_spec.rb:209`, « inverts the exchange rate ») fige l'ancien contrat. La vérification croisée du 2026-09-30 est antérieure au changement de convention de F11, et n'est pas automatisée.
- **Correction** : envoyer `exchange_rate_used` tel quel (8 décimales, la colonne LedgerFlow est `numeric(18,8)`) et remplacer ce test par l'attendu contraire. C'est une modification de BudgetFlow **et** d'un test : elle demande ton accord explicite.
- À ajouter : un test de contrat croisé automatique (mêmes corps, vraie API) pour que cela ne se reproduise pas.

## 3. Décisions à prendre avant de comptabiliser

1. **TVA étrangère.** BudgetFlow n'envoie jamais `vat_treatment` : LedgerFlow applique `domestic` et comptabilise la TVA de chaque ligne comme TVA **belge déductible** (compte de TVA, grille 59). Pour un projet en Zambie, la TVA zambienne (taux à confirmer, p. ex. 16 %) n'est pas déductible dans la déclaration belge. À trancher avec le comptable : TVA étrangère passée en charge (montant TTC en charge, sans TVA) ou compte dédié. Tant que ce n'est pas tranché, ne pas comptabiliser de facture avec TVA hors Belgique. Les codes TVA de BudgetFlow visibles en local sont 0, 6, 12 et 21 (belges) : voir ce que PRODEM utilise.
2. **Factures déjà payées.** Le flux normal suppose : brouillon → comptabilisation → paiement dans LedgerFlow → événement `paid` vers BudgetFlow. Pour une facture 2026 déjà payée dans BudgetFlow, LedgerFlow ne sait rien du paiement : elle restera ouverte (balance âgée fausse) tant que le décaissement n'est pas rapproché (relevé bancaire importé, lettrage). BudgetFlow ignorera l'événement ensuite (déjà payée). Décider : importer les relevés de 2026 d'abord (recommandé), ou n'envoyer que les factures non payées pour ce test.
3. **Comptes et exercice.** LedgerFlow doit avoir un exercice **ouvert** couvrant janvier à octobre 2026 (sinon refus sur la date), un plan comptable et un journal d'achats, des comptes analytiques pour le projet, et les soldes d'ouverture si l'entité avait déjà une comptabilité. Le comptable code lui-même les lignes (compte d'attente 499000 sinon).

## 4. Autres points relevés

- **Les données ne sont pas ici.** La base locale de BudgetFlow ne contient que la démo (7 factures, aucun PRODEM). PRODEM ZAMBIA est dans la base de production de BudgetFlow : je ne peux pas l'inspecter sans accès (décompte par statut, devise, taux de TVA, type d'identifiant fiscal du fournisseur, factures sans lignes, avoirs).
- **Pas d'envoi en masse.** L'export part à la validation d'une facture (`NotifyAccountantJob`). Les factures déjà validées ou payées ne repartent pas seules : il n'existe qu'un bouton par facture. Pour 10 mois de factures, il faut un petit outil d'envoi en masse (une tâche rake), qui espace les appels (limite 300/min par clé, `Retry-After`) et qui est rejouable (les PUT sont idempotents).
- **IBAN.** LedgerFlow contrôle l'IBAN d'un tiers (`422` sinon). Les comptes bancaires zambiens ne sont pas des IBAN : si BudgetFlow y stocke un numéro local, le tiers (et donc la facture) sera refusé. À vérifier sur les fournisseurs réels.
- **Identifiant fiscal.** Seul un identifiant de type `VAT` est envoyé : un TPIN zambien ne l'est pas. Le fournisseur arrive sans numéro, donc sans rapprochement automatique, avec un risque de doublon si le même fournisseur est saisi deux fois.
- **TVA reconstituée.** Une facture sans lignes part en une ligne de synthèse dont le taux est déduit (`vat_amount ÷ amount`, arrondi à 2 décimales) : LedgerFlow peut recalculer une TVA différente de quelques centimes. À comparer.
- **Avoirs** : envoyés sans lien avec la facture d'origine (pas de lettrage). **Reçus** : non exportés. À lister dans l'écart attendu.
- **Cycle de paiement** : la synchronisation est une tâche Solid Queue de BudgetFlow, toutes les 5 minutes. En local, elle ne tourne que si le planificateur est démarré.
- **Préconditions de BudgetFlow** : l'export exige un fournisseur, un journal comptable (la doc dit que ce n'est plus exigé pour LedgerFlow : à confirmer dans `precondition_error`) et au moins une ligne.

## 5. Cadre du test (recommandation)

Ne pas brancher la production de BudgetFlow sur la production de LedgerFlow pour un premier essai : basculer l'adaptateur `ledgerflow` envoie automatiquement chaque facture validée ensuite, pour toute l'entité.

Recommandé :
1. **Copier** la base de production de BudgetFlow (SQLite) sur ton poste (lecture seule, données personnelles : à garder en local) et y lancer BudgetFlow.
2. Dans LedgerFlow de production, créer une **entité de test** « PRODEM ZAMBIA (test) » avec l'option BudgetFlow, un exercice 2026 ouvert, un client API (`partners:write`, `invoices:write`, `invoices:read`).
3. Dans la copie locale de BudgetFlow : adaptateur `ledgerflow`, URL `https://app.ledgerflowmanagment.com`, la clé du client API.
4. Quand le test est concluant, supprimer l'entité de test et refaire le passage sur la vraie entité.

Variante plus simple et moins fidèle : tout en local (LedgerFlow aussi), sans toucher à la production.

## 6. Plan de test par étapes

Chaque étape a un résultat attendu écrit avant de la lancer.

| # | Étape | Contrôle |
|---|---|---|
| 0 | Connexion (`GET /ping`) et scopes | `200`, trois scopes présents |
| 1 | Un fournisseur, puis une facture EUR sans TVA | brouillon visible dans la file « from BudgetFlow », contexte projet et ligne budgétaire affichés |
| 2 | Une facture USD, une en kwacha (après la correction du §2) | total en euros = montant ÷ taux, au centime près |
| 3 | Rejouer le même envoi | aucun changement (idempotence), pas de doublon |
| 4 | Corriger la facture dans BudgetFlow avant que le comptable y touche | brouillon corrigé en place |
| 5 | Le comptable code, comptabilise | événement `posted`, entrée d'audit dans BudgetFlow, numéro comptable |
| 6 | Corriger après comptabilisation | `409` attendu, échec visible et créateur prévenu |
| 7 | « Return to project manager » avec motif | écriture extournée, facture revenue en brouillon dans BudgetFlow avec le motif |
| 8 | Paiement (relevé importé, lettrage) | `paid`, date de valeur, référence bancaire, montant réel dans BudgetFlow |
| 9 | Paiement défait | alerte aux comptables, facture toujours payée dans BudgetFlow (limite connue) |
| 10 | Avoir, facture sans lignes, fournisseur sans TVA, IBAN non valide | comportements du §4 constatés et notés |
| 11 | Volume : toutes les factures 2026 | espacement des appels respecté, aucune erreur 429 non reprise |
| 12 | **Réconciliation** | pour chaque devise : nombre de factures et total BudgetFlow = total LedgerFlow ; total en euros ; TVA ; balance fournisseurs ; `GET /api/v1/projects/:id/accounting_summary` |

## 7. Ce que je propose de construire (après ton accord)

1. **BudgetFlow** (ton accord explicite requis) : correction du taux de change et de son test ; test de contrat croisé ; tâche d'envoi en masse rejouable avec rapport.
2. **LedgerFlow** : un script de réconciliation en lecture seule qui compare les totaux BudgetFlow (export ou copie) et la comptabilité LedgerFlow, par devise et par taux de TVA.
3. Rapport de test consigné ici et alimentant `POINTS_A_VALIDER.md` (nouveaux points : TVA étrangère, IBAN, paiements historiques).

## 8. Questions pour toi

1. D'accord pour corriger le taux de change dans BudgetFlow (et son test) ?
2. Peux-tu me donner accès à une copie de la base de BudgetFlow, ou me fournir les chiffres de PRODEM (décompte par statut, devise, taux de TVA, type d'identifiant fournisseur) ?
3. Test sur copie locale avec une entité de test en production LedgerFlow, ou tout en local ?
4. Factures déjà payées : importer d'abord les relevés bancaires de 2026, ou n'envoyer que les factures non payées pour ce premier essai ?
5. TVA zambienne : en charge (recommandé) ou autre traitement ? À confirmer avec le comptable.

---

## 9. Résultats du test en production (2026-10-25)

Cadre : entités de test **ZZ TEST LedgerFlow** (BudgetFlow) et **ZZ TEST BudgetFlow** (LedgerFlow), en production. Elles resteront dans la comptabilité (chaînée par hachage, non supprimable). Données préparées par `rake ledgerflow:test_setup` dans BudgetFlow : projet `ZZTEST`, engagement `ZZ-TEST-CNT` de 50 000 €, fournisseur `ZZ TEST Supplier SRL`.

| # | Étape (§6) | Résultat | Constat |
|---|---|---|---|
| 0 | Connexion et scopes | **OK** | « Test connection » de BudgetFlow : connecté à l'entité LedgerFlow. Le fournisseur est arrivé dans LedgerFlow. |
| 1 | Facture EUR sans TVA | **OK après correction** | Voir A, B et B' ci-dessous. Brouillon visible dans LedgerFlow, contexte projet et ligne budgétaire affichés, ligne sur 499000. |
| 2 | Facture en devise | **OK** | Facture en USD : le total en euros du brouillon LedgerFlow correspond au montant ÷ taux. La correction du taux de change est donc vérifiée en réel (en plus du test automatique côté LedgerFlow). |
| 3 | Rejeu du même envoi | **Non fait en réel** | Couvert par des tests automatiques (idempotence). |
| 4 | Corriger avant que le comptable y touche | **Non fait** | Aucune modification possible dans BudgetFlow après validation (voir V15). |
| 5 | Le comptable comptabilise | **OK** | Événement `posted` reçu, trace d'audit `ledgerflow_posted`. La fiche BudgetFlow ne montrait rien : corrigé (badge, voir C). |
| 6 | Corriger après comptabilisation | **Impossible depuis l'écran** | BudgetFlow interdit toute modification d'une facture validée. Le `409` n'est atteignable que par l'API. Point V15. |
| 7 | « Return to project manager » | **OK, avec un manque corrigé** | Écriture extournée, facture en brouillon, export à `pending`, e-mail reçu. Le motif n'était affiché que dans le module comptable : corrigé (voir D). Délai jusqu'à 5 minutes, maintenant 1 minute. |
| 8 | Paiement | **OK (lot SEPA)** | Lot créé dans LedgerFlow, fichier généré, « Mark as executed » : la facture est passée à « Paid » dans BudgetFlow (avec le badge « LedgerFlow : Paid »). Le BIC du compte bancaire de l'entité doit être valide, sinon le fichier SEPA est refusé (« Bic is invalid »). Le rapprochement d'un relevé (`payment_confirmed`) : testé à l'étape 14. |
| 9 | Paiement défait | **OK** | Voir le détail ci-dessous (2026-10-27). |
| 10 | Cas limites | **Faits** : A, B et C | A (TVA qui ne tombe pas rond), B (avoir) et C (kwacha, TVA zambienne, fournisseur sans TVA ni IBAN) : voir « Étape 10 » ci-dessous. Le cas « IBAN invalide » est sans objet : BudgetFlow contrôle la clé de l'IBAN. |
| 11 | Volume | **Fait** | 240 factures envoyées en deux lots (un au rythme normal, un à pleine vitesse pour atteindre la limite de débit) : voir « Étape 11 » ci-dessous. |
| 12 | Réconciliation | **Faite, 2 écarts connus** | Après les 240 factures de volume : 250 factures vérifiées, aucun écart nouveau. Voir « Étape 11 » et « Étape 12 » ci-dessous. |
| — | Badge LedgerFlow | **OK** | Une troisième facture a montré « Posted » et le numéro LedgerFlow sur la fiche BudgetFlow, sans rafraîchir. |

### Étape 9 en détail : paiement par relevé, puis paiement défait (2026-10-27)

Chemin suivi : relevé bancaire importé en CSV (une ligne de −100,00, référence `UNDO-TEST-1`), puis « Pay a supplier invoice » dans le rapprochement bancaire. Un lot SEPA ne convient pas : une facture payée par lot n'est pas rouverte par un délettrage.

- **Le paiement est parti sur une autre facture que celle visée.** Deux factures du même fournisseur avaient le même montant (100,0) : la liste déroulante ne les distingue que par le numéro. L'écriture créée s'appelait « Payment ACH2026/0004 », alors que la facture visée était `ACH2026/0007`. Ce n'est pas une erreur de l'application. Le test a continué sur `ACH2026/0004` (`bf-invoice-378`, en USD).
- **L'écran de lettrage ne montre pas les numéros de facture** : « Recent letterings » liste le code du lettrage, le tiers et la date. Le lettrage a été retrouvé par une commande en lecture seule (code `AB`).
- **Facture en USD réglée par un virement de 100,00 €** : le lettrage `AB` rassemblait la facture (89,11 € pour 100 USD), le paiement (100,00 €) et une écriture d'écart de change `OD2026/0001` de 10,89 €. C'est la règle du paiement d'une facture entière : l'écart est comptabilisé tout de suite.
- **Délettrage** (motif obligatoire) : la facture est repassée à « posted » dans LedgerFlow ; le badge de BudgetFlow a suivi et la page s'est mise à jour, conformément au plan (événement `payment_reopened`). Selon l'utilisateur, tout s'est passé « exactement comme prévu », y compris la limite connue : la facture reste « Paid » dans BudgetFlow, qui ne sait pas dé-payer, et les comptables sont prévenus par e-mail.
- **Non vérifié** : que le délettrage ait aussi annulé l'écriture d'écart `OD2026/0001`.
- **Montant reçu par BudgetFlow : correct.** Sur la facture USD, `payment_amount_eur` vaut 100,0 (le débit bancaire réel), `payment_method` `ledgerflow`, référence `UNDO-TEST-1` ; `amount_eur` reste 92,3 (taux de saisie 1,0834). L'audit porte `amount_eur` 100,0 et `fx_difference_eur` −10,89 (une perte). La consommation budgétaire d'une facture payée utilise `payment_amount_eur`. L'écart de change n'est visible que dans l'audit, pas sur la fiche de la facture.

### Étape 11 : volume (2026-10-30)

Données : `ledgerflow:test_volume` crée 120 factures validées par lot dans le projet `ZZTEST` : 12 avoirs en euros, 36 factures en kwacha (24 avec 16 % de TVA, traitées `foreign_vat`), 72 en euros (36 avec 21 % de TVA), du 5 janvier au 25 octobre 2026.

**Lot 1, rythme normal** (une demi-seconde entre deux factures, `ledgerflow:export_invoices[11]` avec `APPLY=1`) : 120 factures envoyées, 0 échec, **99 s, soit 73 factures par minute** (environ 146 appels par minute, la moitié de la limite de 300). Rejeu : plus rien à envoyer. Dans LedgerFlow : 120 brouillons de plus, aucune lenteur de la liste, un avoir retrouvé par la recherche (voir le constat 2). Réconciliation : 130 factures vérifiées, totaux concordants par devise, seul écart nouveau nul (les 0,05 € de TVA arrondie du cas A en euros).

**Lot 2, limite de débit** : 120 nouvelles factures (`BATCH=VOL2`), envoyées par **deux terminaux à la fois, sans pause** (`PAUSE=0`) :
- terminal 1 : 90 factures éligibles (le second avait déjà pris une trentaine de factures), 54 exportées, 36 échecs ; rythme 211 par minute ;
- terminal 2 : 120 éligibles, 85 exportées, 35 échecs ; rythme 199 par minute ;
- les échecs sont lisibles : « LedgerFlow rate limit reached, retry in 10 à 14s » (30 et 31) et « LedgerFlow 409: Concurrent update, retry » (6 et 4) quand les deux envois tentent la même facture au même instant ;
- **rejeu au rythme normal** : 33 factures envoyées, 33 exportées, **0 échec** ;
- **aucun doublon** dans LedgerFlow : 252 factures de l'API pour 250 références (les deux écarts sont les deux factures à deux révisions de l'étape 7), soit exactement 120 de plus qu'avant le lot.

**Réconciliation finale** : 250 factures vérifiées ; kwacha 73 factures, 407 254,16 des deux côtés ; euros 175 factures, 22 964,71 contre 22 964,76 (les 0,05 € du cas A) ; USD 1 facture, 100,0 des deux côtés. Écarts : les deux connus (taux de la facture USD, TVA du cas A) ; manquante : `INV-20261025-A6AEE3` (brouillon supprimé, défaut H, corrigé).

Constats :
1. **Aucune reprise sur la limite de débit.** Quand LedgerFlow refuse (429), BudgetFlow continue d'envoyer les factures suivantes, qui sont toutes refusées jusqu'à la fin de la minute. Au rythme normal la limite n'est jamais atteinte ; à pleine vitesse, c'est le rejeu manuel qui rattrape. **Corrigé** : pendant un envoi en masse, un refus pour limite de débit fait attendre le délai donné (`Retry-After`, plus une seconde) puis réessayer la même facture, trois essais au plus ; un délai de plus de 65 s est rendu comme une réponse, sans attente. Les autres envois (validation d'une facture, synchronisations) restent sans attente.
2. **Les avoirs ne se distinguent pas dans la liste des achats de LedgerFlow** : pas de pastille, pas de filtre par type de document. Une facture est retrouvée par la recherche sur sa description. **Corrigé** : une pastille « Credit note » sur la ligne et un filtre « Credit notes only » dans la liste des achats et des ventes.
3. **Deux envois simultanés** peuvent marquer comme « échouée » dans BudgetFlow une facture que LedgerFlow a bien reçue (le refus de l'un écrase l'état exporté de l'autre). Le rejeu la renvoie sans effet côté LedgerFlow et remet l'état juste. Non observé de façon isolée dans ce test.

Données laissées par le test : 240 factures validées dans le projet `ZZTEST` de BudgetFlow (elles pèsent sur les engagements de test) et 240 brouillons dans l'entité de test de LedgerFlow (hors comptabilité).

### Étape 12 : réconciliation (2026-10-27)

`ledgerflow:reconcile[11]` : 7 factures exportées vérifiées. Totaux concordants : EUR 5 factures, 5122,00 des deux côtés ; USD 1 facture, 100,0 des deux côtés. « Paid here, not paid there yet » : 1 (la facture USD rouverte par le délettrage : normal). « Unknown to BudgetFlow » : 0 ; « Not sent yet » : 0. Deux écarts :

- **Taux de la facture USD** (BudgetFlow 1,0834, LedgerFlow 1,1222 ; 92,30 € contre 89,11 €) : expliqué. Le comptable a modifié le taux du brouillon dans LedgerFlow pour simuler un autre taux de paiement, avant la comptabilisation. La réconciliation l'a bien signalé. Le bon moment pour simuler un taux différent est le paiement (l'écart est alors comptabilisé à part).
- **`INV-20261025-A6AEE3` marquée exportée dans BudgetFlow, inconnue de LedgerFlow** : **expliqué**. Exportée le 25 octobre (identifiant LedgerFlow 1, jamais comptabilisée ni retournée), puis son brouillon a disparu de LedgerFlow : les identifiants des factures de l'API vont de 2 à 8 (`bf-invoice-374` à `380`), l'identifiant 1 manque, et l'audit n'a aucune trace de sa suppression (le modèle de facture n'enregistre pas ses suppressions). Le comptable avait supprimé le brouillon, et BudgetFlow ne pouvait pas le savoir. Corrigé : voir le défaut H.


### Étape 10 : cas limites (2026-10-27)

**Cas A : TVA qui ne tombe pas rond, facture sans lignes.** Facture de 1000,00 € hors TVA, TVA de 123,45 €. BudgetFlow ne transmet pas le montant de TVA mais un taux déduit (TVA ÷ montant, arrondi à deux décimales) : 12,35 %. LedgerFlow l'accepte sans erreur et la comptabilise (statut « posted »). Résultat :
- total 1123,50 € au lieu de 1123,45 € ; TVA 123,50 € au lieu de 123,45 € ;
- la TVA est regroupée par taux **tronqué à l'entier** : écriture « Recoverable VAT 12% » de 123,50 € ;
- la réconciliation le signale (« VAT : BudgetFlow 123.45, LedgerFlow 123.5 ; total en euros : 1123.45 contre 1123.5 ») ; totaux EUR : 6245,45 contre 6245,5.

Conséquences : la TVA déclarable est supérieure de 0,05 € à celle de la facture du fournisseur, et un virement du montant exact laisserait 0,05 € ouverts (LedgerFlow propose un lettrage avec écriture d'arrondi). Rien n'est refusé. Pas un défaut d'envoi : une limite de la reconstitution de la TVA depuis un montant. Voir le point V17 de `POINTS_A_VALIDER.md`.

**Cas B : avoir (note de crédit).** Facture de type « Credit Note (refund) » de 50,00 €, TVA 0, sur `ZZ-TEST-CNT`, sans lien avec une facture d'origine. Résultat conforme au plan, selon l'utilisateur (« tout s'est passé comme prévu ») : brouillon d'avoir dans LedgerFlow, comptabilisation, effet attendu sur la consommation dans BudgetFlow. Le détail de chaque contrôle n'a pas été relevé.

**Cas C : facture en kwacha (ZMW), TVA zambienne de 16 %, fournisseur sans numéro de TVA ni IBAN.** Données préparées par `ledgerflow:test_setup_zambia` (fournisseur « ZZ TEST Supplier Zambia Ltd », TPIN, sans IBAN ; sous-ligne 1.1.2 ; engagement `ZZ-TEST-CNT-ZM` de 1 375 000 ZMW, soit 50 000 € à 27,5). Facture de 10 000 ZMW hors TVA, 1 600 ZMW de TVA, taux de saisie 22,6692304 (441,13 € et 70,58 €). Elle a révélé trois défauts, tous corrigés (voir I, J, K) :
- l'envoi a échoué : la synchronisation du projet était refusée (409), parce que la nouvelle sous-ligne 1.1.2 réutilisait le code d'une sous-ligne supprimée (défaut I) ;
- une fois le projet synchronisé, le comptable a codé la ligne dans LedgerFlow : la **TVA de 16 % a disparu** (le formulaire n'offrait que 0, 6, 12 et 21 % et remettait 0 en silence, défaut J) ;
- la TVA zambienne était comptabilisée comme TVA belge déductible (défaut K).

Résultats une fois les trois corrections déployées, conformes au plan selon l'utilisateur : le kwacha est accepté sans taux officiel (le taux envoyé par BudgetFlow est retenu) ; le traitement de TVA est « Foreign vat » ; la ligne porte 16 % ; la comptabilisation donne une seule ligne de charge de 11 600 ZMW (511,71 €), sans ligne de TVA ni grille de la déclaration belge, et la dette fournisseur du même montant ; le fournisseur arrive sans numéro de TVA, avec les comptes analytiques `ZZTEST` et `ZZTEST-1.1.2`.

### Étape 13 : rattrapage des factures déjà payées, en euros (2026-10-31)

Répétition sur l'entité de test : 20 factures « payées » dans BudgetFlow (lot `PAID1`), un relevé CSV simulé (outil refusant toute entité autre que l'entité de test), envoi à LedgerFlow, comptabilisation, import du relevé, rapprochement.

**Premier essai (lot `PAID1`).** Aucune proposition sur aucune ligne. Les paiements simples ont été réglés à la main par « Pay a supplier invoice ». Causes :

- **L. BudgetFlow n'envoyait pas le numéro de facture du fournisseur** (`supplier_reference`), documenté mais absent de la charge. La règle 2 de LedgerFlow (numéro fournisseur dans le libellé du virement) n'avait rien à chercher.
- **M. Les frais n'étaient reconnus que par le mot « fee »** : « frais », « kosten », « commission » ne l'étaient pas.
- **N. Un virement groupé (un débit, plusieurs factures d'un fournisseur) était impossible** : le paiement fournisseur ne prenait qu'une facture (« single invoice only »), et « Pay a supplier invoice » refuse un montant différent. La ligne est restée en attente.

**Corrections** : BudgetFlow envoie `supplier_reference` et le relevé simulé le met dans le libellé (`c5e14db0`). LedgerFlow reconnaît fee, frais, kosten, bankkosten, commission ; propose, avec « Accept », le paiement groupé quand le libellé cite les références de plusieurs factures d'un même fournisseur dont les totaux égalent le montant (score 80, règle 5) ; offre « Pay several invoices » pour choisir les factures à la main (euros, factures entières, même fournisseur, somme égale au débit) (`d7c4766`).

**Second essai (lot `PAID2`, après redéploiement).** Le bouton « Accept » était présent sur chaque ligne : paiements simples, frais bancaires et virement groupé, et chaque proposition était correcte. Le virement groupé resté en attente du premier essai a été réglé avec « Pay several invoices ». Aucun problème signalé.

`ledgerflow:reconcile[11]` après le rapprochement : 290 factures vérifiées. ZMW 73 factures, 407 254,16 des deux côtés ; USD 1 facture, 100,0 des deux côtés ; EUR 215 factures, BudgetFlow 27 112,11, LedgerFlow 27 112,16 (les 0,05 € du cas A, TVA arrondie). Écarts : uniquement les trois connus (taux de la facture USD, TVA du cas A, `INV-20261025-A6AEE3`). « Paid here, not paid there yet » : 1 (la facture USD, normal tant que son relevé n'est pas importé). « Unknown to BudgetFlow » : 0 ; « Not sent yet » : 0.

Limites : euros seulement ; factures entières ; virement groupé reconnu seulement si le libellé cite les références. Les relevés de PRODEM (kwacha, libellés réels) restent à essayer avec les vrais fichiers.

### Étape 14 : rapprochement du débit d'un lot SEPA, `payment_confirmed` (2026-10-31)

Trois factures en euros de l'entité de test, codées et comptabilisées dans LedgerFlow, payées par un lot SEPA (fichier généré, « Mark as executed » : les trois « Paid » dans BudgetFlow). Puis un relevé CSV d'une seule ligne : le total du lot en négatif, la référence égale à l'identifiant du lot (`message_id`).

- **Rapprochement** : la proposition « payment batch » est apparue avec « Accept » ; un clic, message de réussite. Le débit est lié à l'écriture du lot : rien n'est comptabilisé une seconde fois.
- **BudgetFlow** : l'audit de chacune des trois factures porte `ledgerflow_payment_confirmed`. `ledgerflow:reconcile[11]` : 290 factures, aucun écart nouveau (mêmes totaux et mêmes trois écarts connus que le rattrapage de l'étape 13).
- **Non relevé par l'utilisateur** : la date et la référence de paiement affichées sur la fiche d'une facture après l'événement (le code les met à jour pour une facture payée par LedgerFlow) ; le refus d'un second débit sur un lot déjà lié, et d'un montant faux.
- **O. L'identifiant du lot (`message_id`), nécessaire au rapprochement, n'était affiché nulle part** sur la page d'un lot classique (seulement dans le nom du fichier et la balise `<MsgId>`). Corrigé : « Message id » sur la page d'un lot généré (`ce6e19b`).
- **Piège de saisie** : dans le CSV, le montant doit avoir un point décimal (`-391.62`) ; avec une virgule la ligne a une colonne de trop.

### Défauts trouvés et corrigés pendant le test

- **A. L'écran de clé API ne montrait pas la clé** (LedgerFlow). La création répondait par une page 200 ; Turbo ignore ce type de réponse à un formulaire. La clé était créée mais perdue. Corrigé : formulaires de création et « Rotate key » sans Turbo (`2f523f0`).
- **B. L'envoi attendait une analyse IA qui ne venait jamais** (BudgetFlow). L'export exigeait `ai_analysis_completed?`, or l'analyse est désactivée par défaut : aucune facture ne partait, sans message. Corrigé : pour LedgerFlow, l'envoi n'attend pas une analyse que l'entité n'utilise pas (`e7c3aa38`).
- **B'. Clé API avec un saut de ligne** (BudgetFlow). Un copier-coller avait laissé un retour à la ligne dans la clé enregistrée. `ledgerflow:test_setup` retire maintenant les espaces et sauts de ligne (`d3ada05e`).
- **C. Aucun statut LedgerFlow sur la fiche** (BudgetFlow). Le chef de projet ne voyait pas que la facture était comptabilisée, et le badge d'export laissait un libellé vide pour plusieurs états. Corrigé : colonnes `ledgerflow_status` et `ledgerflow_number`, badge « LedgerFlow : Posted · numéro », tous les états d'export nommés, rafraîchissement automatique toutes les 15 secondes, synchronisation chaque minute (`041fc1a8`).
- **D. Motif du retour invisible pour le chef de projet** (BudgetFlow). Corrigé : bandeau sur la fiche de la facture (`a261f726`).
- **E. Lignes toujours sur 499000** (LedgerFlow). Une ligne sans compte va maintenant sur le compte habituel du fournisseur (celui de sa dernière facture comptabilisée), sinon sur 499000 ; l'empreinte d'idempotence ne dépend pas de ce choix (`0d8c8ec`). **Vérifié en réel** (après redéploiement de LedgerFlow) : la ligne d'une nouvelle facture du même fournisseur est arrivée sur son compte de charge habituel, et non sur 499000.
- **F. La page ne se mettait à jour qu'en partie** (BudgetFlow). Après le paiement, le badge LedgerFlow changeait seul mais pas le statut principal : il fallait rafraîchir. Corrigé : la page entière se recharge quand LedgerFlow fait avancer la facture, avec un vrai test en navigateur (`4038d39a`).
- **G. `budget_line` répétait les codes parents** (BudgetFlow). Les codes de BudgetFlow contiennent déjà leur chemin (chapitre `1`, ligne `1.1`, sous-ligne `1.1.1`) : le texte envoyé donnait `1.1.1.1.1.1`. Corrigé : `1.1.1` (`0d550cb3`).
- **H. Un brouillon venu de BudgetFlow pouvait être supprimé dans LedgerFlow** (LedgerFlow). BudgetFlow le croyait exporté pour toujours, et seule la réconciliation le révélait. Corrigé : la suppression est refusée pour une entité qui utilise BudgetFlow, avec le message qui indique de le retourner au chef de projet, et le bouton « Delete » n'est plus proposé sur ces brouillons ; le retour annule le brouillon et prévient BudgetFlow (`5588075`). Non reproduit en réel après correction.
- **I. Un poste nouveau ne pouvait pas reprendre le code d'un poste supprimé** (LedgerFlow). La synchronisation du projet était refusée (409) : l'ancien compte, désactivé, gardait le code. Corrigé : l'ancien compte cède son code (`code~id`) et garde son historique ; le 409 ne reste que pour un compte réellement étranger, avec un message exact (`ec0f0c5`).
- **J. La TVA d'une ligne disparaissait quand le comptable la codait** (LedgerFlow). La liste des taux du formulaire n'offrait que 0, 6, 12 et 21 % : un taux de 16 % n'y figurait pas, le navigateur prenait le premier choix et l'enregistrement remettait la TVA à 0. Corrigé : le taux de la ligne est ajouté aux choix et sélectionné (`20280d4`).
- **K. La TVA étrangère était comptabilisée comme TVA belge déductible** (LedgerFlow et BudgetFlow). Corrigé : nouveau traitement `foreign_vat` (achats seulement) : la TVA va dans la charge de la ligne, sans ligne de TVA ni grille belge ; BudgetFlow l'envoie quand le fournisseur n'est pas belge et que la facture porte de la TVA (`744c882`, `acc6b5ab`). Questions pour le comptable : point T12 de `POINTS_A_VALIDER.md`.

### Constats sans correction (décisions à prendre, voir `POINTS_A_VALIDER.md`)

- **V14** : le module comptable de BudgetFlow ne sert presque plus pour une entité LedgerFlow ; ne pas le supprimer tant que Dolibarr et WinBooks sont supportés.
- **V15** : « Dispute » dans BudgetFlow ne prévient pas LedgerFlow ; une facture peut être en litige d'un côté et comptabilisée de l'autre.
- **Piège de l'interface** : « Pay a supplier invoice » ne distingue pas deux factures du même tiers et du même montant, et l'écran de lettrage n'affiche pas les numéros de facture. À améliorer si les chefs de projet ou les comptables s'en plaignent.
- Aide au codage par l'IA côté LedgerFlow (compte, TVA, analytique par ligne) : n'existe pas ; écarté pour l'instant (palier B, à décider après un pilote).

## 10. Comptes analytiques projet et poste (2026-10-27)

Objectif : que BudgetFlow crée dans LedgerFlow les comptes analytiques de ses projets et de ses postes budgétaires, et que chaque ligne de facture soit annotée automatiquement, pour lire la consommation budgétaire dans la comptabilité.

Décisions : un compte par sous-ligne sur l'axe `BUDG` (hiérarchie dans le code et le libellé), un compte par projet sur `PROJ` ; codes seulement (les montants et le rapport budget contre réel sont une phase 2) ; annotation automatique que **le comptable ne peut pas modifier** (il retourne la facture) ; BudgetFlow commande les comptes, LedgerFlow les protège ; un poste retiré est désactivé, jamais supprimé ; un projet ou un poste inconnu fait refuser la facture (422) ; un projet clôturé désactive ses comptes.

Construit : LedgerFlow `1947cbd` (`PUT /api/v1/projects/:ref`, droit `analytical:write`, `project_ref` et `budget_line_ref` sur la facture, verrou côté serveur et à l'écran), BudgetFlow `0d550cb3` (envoi à la création, au changement de nom, de code ou de statut et au verrouillage du budget ; tâche de rattrapage `ledgerflow:sync_projects`).

| Vérification en production | Résultat |
|---|---|
| Nouveau client API avec `analytical:write`, « Test connection » | **OK** |
| Rattrapage `ledgerflow:sync_projects[11]` (aperçu, puis envoi) | **OK** : 1 projet synchronisé, 0 échec |
| Compte `PROJ` du projet, marqué « Managed by BudgetFlow » | **OK** |
| Verrouillage du budget : comptes `BUDG` des postes | **OK** |
| Facture sur le projet : lignes annotées `PROJ` et `BUDG`, non modifiables par le comptable | **OK** |
| Poste ajouté, poste retiré (désactivé), projet clôturé | **OK** |

Points à connaître :
- Les droits d'un client API existant ne se modifient pas : il a fallu créer un nouveau client avec `analytical:write`.
- Les comptes gérés par BudgetFlow sont entièrement en lecture seule dans les réglages de LedgerFlow (le comptable ne peut pas non plus les désactiver), pour qu'un envoi ne réactive pas ce qu'il aurait désactivé. Écart voulu avec l'énoncé « il peut seulement les désactiver ».
- Les factures déjà comptabilisées avant cette fonction restent sans analytique tant que le comptable ne les retourne pas.
- Pas encore fait : les montants budgétaires et le rapport budget contre réel (R11) ; l'obligation d'avoir `PROJ` et `BUDG` sur les charges de classe 6 avant de comptabiliser (décision différée, voir `POINTS_A_VALIDER.md`).

### Reste à faire avant PRODEM ZAMBIA

Correction avant comptabilisation (étape 4) ; décisions sur la TVA zambienne (point T12 : les questions pour le comptable), les factures déjà payées en kwacha et avec de vrais relevés (la répétition en euros est faite, étape 13), l'IBAN et le TPIN (§3 et §4). Puis nettoyage : révoquer le client API « BudgetFlow test » (ses clés sont passées dans une conversation) et recréer un client propre pour l'usage réel.

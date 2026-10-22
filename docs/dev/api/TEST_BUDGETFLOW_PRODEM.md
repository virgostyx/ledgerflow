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

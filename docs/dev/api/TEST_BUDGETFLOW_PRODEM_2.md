# Test réel ECES test / PRODEM ZAMBIA (PROJ-2026-001) — démarré le 2026-11-05

Plan : `~/.claude/plans/rosy-dazzling-locket.md`. Suite du test `TEST_BUDGETFLOW_PRODEM.md` (entités ZZ TEST).

## Décisions
- Entité LedgerFlow de production « ECES test » (plan ASBL, exercice 2026 ouvert, sans reprise). PRODEM ZAMBIA = compte analytique `PROJ-2026-001` géré par BudgetFlow.
- BudgetFlow : entité ECES (un seul projet : PRODEM), adaptateur `none` → `ledgerflow`. Seules les factures validées à partir du 2026-11-05 partent.
- TVA : entité assujettie, TVA déductible (régime normal) ; **périodicité à confirmer** (mensuelle / trimestrielle).
- TVA zambienne : **en charge** (`foreign_vat`, point T12 de `POINTS_A_VALIDER.md`), décidé le 2026-11-05.
- Flux externes : B2Brouter clé `test_` (à confirmer), INTERVAT = XML sans dépôt, e-mails factices, relevés fabriqués.

## Garde-fous (à relire avant chaque action)
- [ ] Jamais d'envoi en masse sans filtre de date ≥ 2026-11-05 et sans aperçu préalable.
- [ ] Paiements fictifs : seulement sur des factures de test (fournisseur « ZZ ») ou acceptées comme « payées ».
- [ ] Aucun e-mail vers une adresse réelle ; aucune clé Peppol de production.
- [ ] Client API « BudgetFlow test » révoqué, nouveau client avec 4 scopes.

## Journal des étapes (attendu écrit AVANT l'étape, constat après)
| # | Étape | Attendu | Constat | OK |
|---|---|---|---|---|
| A1 | Créer l'entité « ECES test » (ASBL) | exercice 2026 ouvert, journaux, axes PROJ/ACT/FIN/BUDG | | |
| A2 | Paramètres : TVA, `iban_cooling_hours=0`, politique taux ZMW, drapeaux | enregistrés | | |
| A3 | Caisse ZMW + banque EUR + banque ZMW | comptes créés, BIC valide | | |
| A4 | Utilisateurs de test, isolation vs ECES réelle | aucune donnée ECES visible | | |
| A5 | Client API + `EntitySetting` BudgetFlow + Test connection | 200, 4 scopes | | |
| A6 | `ledgerflow:sync_projects` (aperçu puis envoi) | compte PROJ-2026-001 + BUDG | | |
| B1 | Facture EUR sans TVA | brouillon, contexte projet/ligne | | |
| B2 | Facture ZMW, TVA 16 % en charge | `foreign_vat`, total EUR = ZMW ÷ taux, pas de ligne TVA | | |
| B3 | USD, avoir, facture sans lignes | écarts connus seulement | | |
| B4 | Comptabilisation | `posted`, badge BudgetFlow | | |
| B5 | Retour au chef de projet, renvoi, 409 | motif visible, brouillon | | |
| B6 | Lot SEPA puis relevé `payment_confirmed` | `paid` puis audit | | |
| B7 | Relevés : simple, groupé, frais, ZMW, Undo | propositions Accept correctes | | |
| B7bis | Caisse ZMW : alimentation, paiement, Undo | événement `paid` reçu par BudgetFlow ? | | |
| B8 | `ledgerflow:reconcile` | écarts connus seulement | | |
| C1 | Peppol B2Brouter test : envoi / réception | succès, refus, sans destinataire | | |
| C2 | Mail documents + quarantaine | pièce en inbox, expéditeur non autorisé en quarantaine | | |
| C3 | TVA : déclaration + XML INTERVAT | XML téléchargé, aucune soumission externe | | |
| D | Répétition de la démo investisseurs | 15–20 min sans accroc | | |

## Écarts et défauts trouvés
(à remplir)

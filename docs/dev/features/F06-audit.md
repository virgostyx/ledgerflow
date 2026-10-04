# F06 — Facturation électronique Peppol : audit de l'existant (étape 0)

Avancement : **F06 est livrée, voir `F06.md`** (étapes 1 à 6 faites). Décisions 1 (B2Brouter, code commun modifiable), 4 (brouillon de **facture fournisseur** avec lignes) et 5 (devises traitées comme les autres) **validées le 2026-10-04** ; **étape 1 faite** (voir `QUESTIONS.md` § F06). Les décisions 2, 3, 6 et 7 restent ouvertes.

Statut à la date de l'audit : **audit seul, aucun code modifié.** La spec (§9, « Étape 0 ») demande de s'arrêter ici et d'attendre une validation avant de toucher à l'existant. Ce document dit ce qui est en place, ce qui manque par rapport à la spec, ce que j'ai vu de risqué, les décisions qui te reviennent et l'ordre de travaux proposé.

Lu : `app/services/peppol/**`, `app/controllers/peppol/webhooks_controller.rb`, `app/controllers/accounting/settings/peppol_settings_controller.rb`, `app/models/accounting/peppol_event.rb`, `config/initializers/peppol.rb`, la structure de base, les routes, les politiques, `docs/dev/HANDOFF_next_steps.md` §3c. Les affirmations sur le sandbox B2Brouter viennent du HANDOFF : je ne les ai pas rejouées.

## 1. Ce qui existe

**Un adaptateur par fournisseur d'Access Point**, choisi par société (`entities.peppol_access_point`, `peppol_participant_id` unique, `peppol_credentials` chiffré, `peppol_webhook_token` unique). Interface `Peppol::AccessPoint::Base` : `send_document`, `registered?`, `parse_webhook`, `credential_fields`.

| Adaptateur | État |
|---|---|
| `Simulator` | Pour le développement et les tests (refusé hors dev/test). Scénarios `…-FAILED`, `…-UNREGISTERED`, `…-SLOW`, réception simulée. |
| `Digiteal` | **Écrit de mémoire, jamais confronté à la documentation ni à un compte** (chemins, champs JSON, événements et en-tête de signature sont des hypothèses). Son propre en-tête le dit. Non utilisable en production. |
| `B2brouter` | Écrit d'après la documentation officielle et un import réel de notre UBL dans leur sandbox. Envoi (import puis `send_invoice`), annuaire (`/directory/be/<valeur>`), webhook de changement d'état avec signature HMAC (`X-B2Brouter-Signature`, `t=…,s=…`) : exécutés pour de vrai dans le sandbox d'après le HANDOFF. **La réception n'est pas gérée** (webhook non documenté dans ce qui avait été lu). |

**Envoi** (`Peppol::SendInvoice` : `ValidateSendable` → `BuildUblXml` → `SendViaAccessPoint` → `HandleDeliveryStatus`) : facture de vente validée, émetteur et destinataire connus, e-mail de l'acheteur exigé par B2Brouter, destinataire vérifié dans l'annuaire (refus s'il est inconnu, silence si l'annuaire ne répond pas ou si le schéma n'est pas belge). Statuts sur la facture (`peppol_id` unique, `peppol_status`) et historique dans `accounting_peppol_events` (envoyé, livré, échec). Les notes de crédit partent en `CreditNote` 381 avec `BillingReference`. Un renvoi dont le numéro existe déjà chez B2Brouter adopte la facture partie ou remplace celle restée en `new`/`error`.

**UBL** (`UblInvoiceBuilder`) : BIS Billing 3.0 (`CustomizationID`, `ProfileID`), émetteur d'après la société, `EndpointID`, adresses, `BuyerReference`, `PaymentMeans` (premier compte actif), catégories de TVA S/Z/E/AE/K/G avec motif d'exonération, d'après le régime de TVA de la facture (codé en dur dans le constructeur).

**Réception** (`Peppol::HandleEvent` puis `Peppol::ReceiveInvoice`) : un événement « reçu » est routé vers la société par son identifiant Peppol, dans son exercice ouvert ; l'UBL devient un **brouillon de facture fournisseur** (en-tête seulement) qui garde l'XML d'origine, le PDF intégré (≤ 15 Mo), `OrderReference` et `BuyerReference`. Doublon : même fournisseur et même numéro, hors facture annulée. Avoir reçu : brouillon de type note de crédit.

**Webhook** : `POST /peppol/webhooks/:token` (public, jeton par société), signature vérifiée par l'adaptateur, événements normalisés (`Peppol::Event`). **Réglages** : carte « Peppol » (identifiants déclarés par l'adaptateur, secrets jamais réaffichés). **Facture** : bouton d'envoi, statut, historique ; champ Peppol sur la fiche partenaire (défaut `0208:` + TVA belge).

## 2. Écarts avec la spec

| Spec §9 | État | Constat |
|---|---|---|
| `peppol_messages` (sens, identifiant, expéditeur, destinataire, type, processus, statut, XML, erreurs) | ❌ | Aucun enregistrement du message reçu. Seuls existent `accounting_peppol_events` (liés à une **facture** déjà créée) et deux colonnes sur la facture. |
| Idempotence par identifiant de message | ❌ | Le doublon est détecté par fournisseur + numéro, pas par message. |
| `peppol_participants` | 🟡 | Une colonne de `entities`. Pas de statut d'enregistrement. Suffit pour une société par Access Point. |
| `supplier_defaults`, `vat_category_mappings` | ❌ | Catégories UBL en dur dans le constructeur ; aucune proposition de compte, de code TVA ni de journal d'après le fournisseur. |
| XML et PDF stockés dans F03 | ❌ | Ils sont attachés à la facture (Active Storage), pas au magasin de documents F03 ; pas de rendu lisible quand il n'y a pas de PDF. |
| Mappeur `Peppol::InvoiceMapper` (facture canonique complète) | ❌ | `ReceiveInvoice` lit une poignée de nœuds avec `//ID` etc. Ni lignes, ni remises et frais du document, ni catégories de TVA par ligne, ni IBAN, ni BCE, ni moyen de paiement, ni communication structurée. |
| Contrôles (somme des lignes, TVA par catégorie à 0,01 €, TVA belge modulo 97, devise, échéance, doublon) | ❌ | Seuls les champs obligatoires sont vérifiés. |
| Statut `needs_review` avec raisons | ❌ | Voir risque n° 1. |
| Tiers : recherche TVA, BCE, IBAN ; inconnu créé « à valider » | 🟡 | Recherche par numéro de TVA seulement. Un inconnu est créé en fournisseur, **pays « BE » en dur**, sans statut « à valider ». |
| Brouillon d'écriture (charge par catégorie, TVA, dette 440 avec échéance et communication structurée) | ❌ | Le brouillon est une facture **sans ligne** : rien à valider tel quel, la communication structurée n'est pas conservée (donc pas d'alimentation de la règle 1 de F02/F04). |
| Avoir lié à la facture d'origine, proposition de lettrage | 🟡 | Type avoir ; `BillingReference` non lue, pas de lien. |
| Documents Peppol qui ne sont pas des factures : stockés sans écriture | ❌ | Non traités. |
| Devise étrangère : `needs_review` jusqu'à F11 | ⚠ | Dépassé : les factures sont déjà multi-devises. À trancher (voir §4). |
| Émission : PDF en pièce jointe de l'UBL | ❌ | Le constructeur n'ajoute aucune pièce jointe. |
| Validation schematron avant envoi | ❌ | Non faite. Décision à prendre. |
| Repli e-mail si le destinataire n'est pas joignable | ❌ | Refus seulement. `InvoiceMailer` existe et pourrait servir. |
| Trois tentatives avec attente croissante | ❌ | Une seule tentative, pas de job. |
| XML envoyé et accusé stockés dans F03 | ❌ | |
| Écrans « Factures reçues », « Factures envoyées », tableau de suivi | ❌ | Aucun. |
| Permissions `peppol.review`, `peppol.send`, `peppol.configure` | ❌ | Envoi = `invoices.issue` ; réglages = administrateur. |
| Webhook : signature, liste blanche, rejet journalisé | 🟡 | Signature vérifiée (401 si fausse). **Pas de fenêtre de fraîcheur** sur l'horodatage `t` (un message signé peut être rejoué), pas de liste blanche, **le rejet n'est pas journalisé** (critère 7). |
| Bandeau « test » visible | ❌ | |
| Aucun brouillon validé sans action humaine | ✅ | Tout est créé en brouillon. |

## 3. Risques constatés dans l'existant

1. **Perte silencieuse d'un document reçu.** Si `ReceiveInvoice` échoue (champ manquant, numéro de TVA absent…), le webhook écrit un avertissement dans le journal et répond **200** : l'Access Point considère le document livré, et nous n'en gardons rien (l'XML n'est stocké qu'à la création de la facture). Avec la réception réelle, c'est le risque le plus sérieux. C'est ce que `peppol_messages` et `needs_review` corrigent, et c'est pourquoi je les mettrais en premier.
2. **Mappeur fragile.** `//ID` prend le premier `ID` du document ; un UBL dont l'ordre diffère donne un mauvais numéro. Pas testé sur les fichiers d'exemple officiels (critère 1 de la spec).
3. **Fournisseur créé avec « BE » en dur** et sans statut à valider : un fournisseur étranger est faussé, et rien ne signale qu'il a été créé par la machine.
4. **Facture sans ligne** : la valider donne une écriture sans charge ni TVA.
5. **Replay du webhook** : l'horodatage est signé mais jamais comparé à l'heure courante.
6. **Digiteal** : adaptateur non validé, encore sélectionnable dans les réglages.
7. **Conformité UBL non vérifiée** : aucune règle schematron n'a été exécutée sur nos fichiers émis.

## 4. Décisions qui te reviennent

1. **Access Point visé : B2Brouter** (la spec dit Digiteal). Je laisse l'adaptateur Digiteal intact. J'ai besoin de ton accord pour modifier le code commun à tous les adaptateurs (réception, mappeur, contrôles), la spec interdisant de toucher à l'intégration existante sans accord.
2. **Plan gratuit de B2Brouter** : à vérifier dans ton compte, je ne le sais pas : réception par webhook ou API, validation avant envoi, volumes et limites du sandbox.
3. **Validation avant envoi** : (a) service de validation de B2Brouter, si le plan l'inclut (aucun entretien de notre côté, dépend du fournisseur et de son plan) ; (b) schematron local (règles officielles OpenPeppol, exécutées par un utilitaire dans l'application : gratuit, indépendant du fournisseur, mais les règles sont à mettre à jour à chaque version publiée et il faut un moteur XSLT 2 : Saxon, donc Java, ou une alternative à évaluer). Je te chiffrerai les deux avant de choisir, comme la spec le demande.
4. **Brouillon de réception : facture fournisseur ou écriture ?** La spec demande un brouillon d'**écriture** dans le journal d'achats. L'application a déjà le chemin « facture fournisseur brouillon avec lignes → validation → écriture » (TVA, tiers, BudgetFlow, lettrage, état payé). Je propose de **créer un brouillon de facture fournisseur avec ses lignes** et de laisser la validation produire l'écriture, plutôt que de fabriquer une écriture à côté. C'est un écart avec la lettre de la spec, à valider.
5. **Devise étrangère** : la spec la met en `needs_review` jusqu'à F11, ce qui est dépassé ici. Je propose de la traiter comme les autres factures, en conservant la devise et le taux du document.
6. **Accès de test** pour la réception : un identifiant Peppol de test sur le sandbox et un exemple réel de webhook de facture reçue. Sans cela la réception B2Brouter ne sera testée qu'avec le simulateur et des payloads inventés, et je le dirai.
7. **Fichiers d'exemple officiels Peppol BIS Billing 3.0** (critère 1) : je comptais les télécharger depuis le dépôt officiel d'OpenPeppol. Je te demande l'accord de télécharger ces fichiers dans `spec/fixtures/files/peppol/` (sources et taille annoncées avant), ou de me les fournir.

## 5. Ordre de travaux proposé

0. **Ta validation de ce document** et des décisions 1, 4 et 5.
1. **Filet de sécurité** : `peppol_messages` (tout message entrant et sortant, avec son XML dans F03), idempotence par identifiant de message, `needs_review` ; le webhook ne répond plus 200 pour un document qu'il a perdu. Rejet de signature journalisé, fenêtre de fraîcheur de l'horodatage.
2. **Mappeur** `Peppol::InvoiceMapper` sur les exemples officiels (facture, avoir, remises et frais, autoliquidation), puis les contrôles (totaux, TVA par catégorie, TVA belge, devise, échéance, doublon).
3. **Tiers et comptes** : recherche TVA, BCE, IBAN ; fournisseur inconnu « à valider », pays lu du document ; `supplier_defaults` et `vat_category_mappings` (données modifiables) ; brouillon de facture avec lignes et communication structurée conservée.
4. **Écrans et droits** : « Factures reçues » (création du brouillon, en lot pour les messages sans anomalie, correction de `needs_review`), « Factures envoyées », tableau de suivi ; `peppol.review`, `peppol.send`, `peppol.configure`.
5. **Émission** : PDF en pièce jointe, validation avant envoi (selon la décision 3), trois tentatives, repli par e-mail, XML et accusé dans F03.
6. **Réception réelle chez B2Brouter** : dépend des décisions 2 et 6 ; en attendant, le reste est testé avec le simulateur et les fichiers officiels.

Chaque étape : TDD, suite complète verte, F06.md et critères d'acceptation cités un par un à la fin. Les critères 1 à 8 de la spec §9 sont couverts par les étapes 1 à 5 ; seul le critère 5 (rapprochement par communication structurée) dépend de l'étape 3.

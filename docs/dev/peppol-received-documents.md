# Factures reçues par Peppol : ce qui est conservé

Statut : implémenté (2026-10-01). Concerne **toutes** les entités qui reçoivent des factures par Peppol (pas seulement celles qui utilisent BudgetFlow).
Code : `app/services/peppol/receive_invoice.rb`, `Accounting::InvoicesController#document`, `app/views/accounting/invoices/_peppol_document.html.erb`.

## Ce qui est gardé
Un document UBL reçu devient un brouillon de facture fournisseur (comme avant) et **garde désormais** :

| Quoi | Où | Remarque |
|---|---|---|
| Le XML UBL tel que reçu, **octet pour octet** | `invoice.ubl_document` (Active Storage) | L'original de la facture électronique. Toujours conservé. |
| Le PDF que le fournisseur a embarqué dans le XML | `invoice.pdf_document` | Seulement s'il existe : `cac:AdditionalDocumentReference/cac:Attachment/cbc:EmbeddedDocumentBinaryObject`, `mimeCode="application/pdf"`. |
| La référence de commande | `invoice.order_reference` | `cac:OrderReference/cbc:ID` (par exemple un numéro de bon de commande ou d'engagement). |
| La référence acheteur | `invoice.buyer_reference` | `cbc:BuyerReference` (par exemple un code projet). |

La fiche facture affiche un bloc « Peppol document » (références, lien vers le PDF dans le navigateur, téléchargement du XML d'origine). L'accès passe par `GET /accounting/invoices/:id/documents/(pdf|xml)` : mêmes droits que la fiche, jamais d'adresse publique.

## Règles et limites
- **Pas de PDF séparé** : les points d'accès (Digiteal, simulateur) ne livrent que le XML. Sans PDF embarqué par le fournisseur, il n'y a que le XML. Aucun PDF n'est généré.
- **Un « PDF » embarqué doit en être un** : déclaré `application/pdf`, commençant par `%PDF`, de 15 Mo au plus. Sinon il est ignoré (la facture est reçue, le XML est gardé). Aucune analyse antivirus.
- **Livraison en double** : un point d'accès peut envoyer deux fois le même document. Une facture déjà reçue (même fournisseur, même numéro, non annulée) est renvoyée au lieu de créer un second brouillon. Un numéro identique d'un autre fournisseur, ou après annulation, donne une nouvelle facture.
- **Tout ou rien** : la facture, le fournisseur éventuellement créé et ses documents sont enregistrés ensemble ; si le stockage échoue, rien ne reste.
- **B2Brouter** : la réception n'est pas gérée (webhook non documenté) ; inchangé.

## Exploitation
Les fichiers sont stockés par Active Storage sur le disque du serveur : volume `ledgerflow_storage:/rails/storage` (`config/deploy.yml`, service `local`). **Ce volume doit être sauvegardé** : l'original d'une facture reçue est une pièce à conserver. Les enregistrements correspondants sont dans `active_storage_blobs` et `active_storage_attachments` (base principale).

## Suite prévue
La référence de commande est la clé de rapprochement avec un engagement BudgetFlow (numéro de contrat ou de bon de commande) : la « boîte de réception » BudgetFlow, qui rattache une facture Peppol à un engagement par le gestionnaire de projet, s'appuiera dessus. Non faite.

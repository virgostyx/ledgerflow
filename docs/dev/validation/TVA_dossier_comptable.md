# LedgerFlow — Dossier de validation TVA pour le comptable

Date : 2026-11-02. Entité visée en premier : **ASBL**. Périmètre : TVA seule (points T1, T2, T3, T7, T12 de `docs/dev/POINTS_A_VALIDER.md`).

## 1. Ce que l'on vous demande

Comparer, pour chaque cas de la section 3, **ce que LedgerFlow comptabilise et déclare** avec **ce que vous déclareriez**. Pour chaque cas, cochez « conforme » ou indiquez la correction. Les sections 4 et 5 posent les questions qui ne se règlent pas par un cas chiffré.

## 2. Limites à connaître avant de lire

- Aucun comptable n'a relu ces règles. Le tableau des grilles a été reconstruit d'après la **notice explicative du SPF Finances de janvier 2014**, à recouper avec une notice récente.
- Le fichier XML Intervat est validé contre un XSD **v0.7 de 2012, copie tierce**, pas contre le XSD officiel. **Ne rien déposer de ce XML** ; saisir la déclaration à la main dans Intervat à partir des grilles ci-dessous.
- Limites connues de la déclaration (T3) :
  - la TVA non déductible n'est pas ajoutée aux bases 81–83 (notice n°161) ;
  - la part privée n'est pas gérée (n°160) ;
  - pas de plancher à zéro ni de report sur la période suivante après avoir (n°163, 198) : une grille peut sortir négative ;
  - grilles 57 (import avec report de perception) et 91 (acompte de décembre) non gérées ;
  - avoirs postés avant le changement de mapping non migrés.
- Les cas ci-dessous sont **réels** : chacun a été comptabilisé avec les services de l'application (`PostInvoice`, puis `GenerateVatReturn` sur l'année), dans une base de test isolée. Chaque cas part d'une période vide. Entité de test : assujettie, TVA belge déductible, sans prorata.

## 3. Tableau des grilles et cas chiffrés

### 3.1 Tableau des grilles appliqué

**Ventes (base HT)** : domestique 6 % → 01 ; 12 % → 02 ; 21 % → 03 ; TVA due → 54. Autoliquidation par le client (construction) → 45. Intracom biens → 46. Intracom services B2B → 44. Export et autres exonérations → 47. Avoir : base en 49 (sauf sur 44/46 → 48), TVA de l'avoir en 64 ; le HT de l'avoir ne diminue jamais 01–03.

**Achats (base HT)** : domestique par nature de compte : 600–605 → 81 ; 61 et 64 → 82 ; classe 2 (20–27) → 83 ; TVA déductible → 59. Autoliquidation : intracom biens → 86 (+ TVA due 55) ; intracom services → 88 (+ 55) ; autres autoliquidations → 87 (+ TVA due 56). Les grilles 86/87/88 **s'ajoutent** à 81–83. Avoir : 85 (84 si l'opération d'origine était en 86/88), TVA de l'avoir en 63.

**Totaux** : XX = 54+55+56+57+61+63 ; YY = 59+62+64 ; 71 = XX−YY si positif, 72 = YY−XX si négatif.

### 3.2 Cas

### C01 Vente domestique 21 %
Vente de 1000,00 HT, TVA 21 %.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1210.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 3 | 1000.00 |
| 450100 | 0.00 | 210.00 | 54 | 210.00 |

**Déclaration produite** : grille 03 = 1000.00 ; grille 54 = 210.00 ; grille 71 = 210.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C02 Vente domestique 6 %
Vente de 1000,00 HT, TVA 6 %.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1060.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 1 | 1000.00 |
| 450100 | 0.00 | 60.00 | 54 | 60.00 |

**Déclaration produite** : grille 01 = 1000.00 ; grille 54 = 60.00 ; grille 71 = 60.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C03 Vente domestique 12 %
Vente de 1000,00 HT, TVA 12 %.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1120.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 2 | 1000.00 |
| 450100 | 0.00 | 120.00 | 54 | 120.00 |

**Déclaration produite** : grille 02 = 1000.00 ; grille 54 = 120.00 ; grille 71 = 120.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C04 Achat domestique, compte 604 (marchandises/services)
Achat de 1000,00 HT, TVA 21 % déductible.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 604000 | 1000.00 | 0.00 | 81 | 1000.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1210.00 |  |  |

**Déclaration produite** : grille 59 = 210.00 ; grille 72 = 210.00 ; grille 81 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C05 Achat domestique, compte 61 (services et biens divers)
Loyer de 1000,00 HT, TVA 21 %.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 610100 | 1000.00 | 0.00 | 82 | 1000.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1210.00 |  |  |

**Déclaration produite** : grille 59 = 210.00 ; grille 72 = 210.00 ; grille 82 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C06 Achat domestique, classe 2 (immobilisation)
Ordinateur de 1000,00 HT, TVA 21 %.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 240200 | 1000.00 | 0.00 | 83 | 1000.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1210.00 |  |  |

**Déclaration produite** : grille 59 = 210.00 ; grille 72 = 210.00 ; grille 83 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C07 Vente intracommunautaire de biens
Livraison de 1000,00 à un client assujetti français.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1000.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 46 | 1000.00 |

**Déclaration produite** : grille 46 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C08 Vente intracommunautaire de services B2B
Prestation de 1000,00 à un client assujetti français.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1000.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 44 | 1000.00 |

**Déclaration produite** : grille 44 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C09 Achat intracommunautaire de services
Service de 1000,00 d'un fournisseur français, TVA belge 21 % autoliquidée.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 610100 | 1000.00 | 0.00 | 88 | 1000.00 |
| 450100 | 0.00 | 210.00 | 55 | 210.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1000.00 |  |  |

**Déclaration produite** : grille 55 = 210.00 ; grille 59 = 210.00 ; grille 82 = 1000.00 ; grille 88 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C10 Achat intracommunautaire de biens
Biens de 1000,00 d'un fournisseur français, TVA belge 21 % autoliquidée.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 604000 | 1000.00 | 0.00 | 86 | 1000.00 |
| 450100 | 0.00 | 210.00 | 55 | 210.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1000.00 |  |  |

**Déclaration produite** : grille 55 = 210.00 ; grille 59 = 210.00 ; grille 81 = 1000.00 ; grille 86 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C11 Vente avec autoliquidation (construction)
Travaux de 1000,00, client belge, cocontractant.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1000.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 45 | 1000.00 |

**Déclaration produite** : grille 45 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C12 Achat avec autoliquidation (sous-traitance construction)
Travaux de 1000,00, TVA 21 % autoliquidée.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 610100 | 1000.00 | 0.00 | 87 | 1000.00 |
| 450100 | 0.00 | 210.00 | 56 | 210.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1000.00 |  |  |

**Déclaration produite** : grille 56 = 210.00 ; grille 59 = 210.00 ; grille 82 = 1000.00 ; grille 87 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C13 Exportation hors UE
Vente de 1000,00 à un client américain.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1000.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 47 | 1000.00 |

**Déclaration produite** : grille 47 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C14 Vente domestique 21 % puis note de crédit de 300,00
Facture de 1000,00 HT puis avoir de 300,00 HT.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1210.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 3 | 1000.00 |
| 450100 | 0.00 | 210.00 | 54 | 210.00 |
| 400000 | 0.00 | 363.00 |  |  |
| 700000 | 300.00 | 0.00 | 49 | 300.00 |
| 450100 | 63.00 | 0.00 | 64 | 63.00 |

**Déclaration produite** : grille 03 = 1000.00 ; grille 49 = 300.00 ; grille 54 = 210.00 ; grille 64 = 63.00 ; grille 71 = 147.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C15 Achat domestique 21 % puis note de crédit de 300,00
Facture fournisseur de 1000,00 HT puis avoir de 300,00 HT.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 604000 | 1000.00 | 0.00 | 81 | 1000.00 |
| 410100 | 210.00 | 0.00 | 59 | 210.00 |
| 440000 | 0.00 | 1210.00 |  |  |
| 604000 | 0.00 | 300.00 | 81 | -300.00 |
| 410100 | 0.00 | 63.00 | 63 | 63.00 |
| 440000 | 363.00 | 0.00 |  |  |

**Déclaration produite** : grille 59 = 210.00 ; grille 63 = 63.00 ; grille 72 = 147.00 ; grille 81 = 700.00 ; grille 85 = 300.00

- [ ] conforme  - [ ] à corriger : ________________________________


### C16 Achat étranger avec TVA locale (foreign_vat)
Facture zambienne de 1000,00 + 16 %, TVA non récupérable.

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 604000 | 1160.00 | 0.00 |  |  |
| 440000 | 0.00 | 1160.00 |  |  |

**Déclaration produite** : 

- [ ] conforme  - [ ] à corriger : ________________________________


### C17 Vente domestique à 0 %
Vente de 1000,00 HT sans TVA (exonération simple).

**Écriture comptabilisée**
| Compte | Débit | Crédit | Grille | Montant grille |
|---|---:|---:|---:|---:|
| 400000 | 1000.00 | 0.00 |  |  |
| 700000 | 0.00 | 1000.00 | 0 | 1000.00 |

**Déclaration produite** : grille 00 = 1000.00

- [ ] conforme  - [ ] à corriger : ________________________________


### 3.3 Écarts que nous avons déjà repérés dans ces résultats

- **C17** : une vente à 0 % ordinaire va en **grille 00**. La notice réserve la 00 aux régimes particuliers (tabac, journaux…). Faut-il la mettre en 47 (exonérée), ou refuser le taux 0 % ?
- **C09, C10, C12** : l'autoliquidation produit **deux** grilles de base (82 *et* 88, 81 *et* 86, 82 *et* 87), conformément à la notice (n°161-2). À confirmer, car le total des bases est alors double de la facture.
- **C15** : l'avoir fournisseur ramène la grille 81 de 1000 à 700 *et* inscrit 300 en 85. À confirmer.

## 4. Questions propres à une ASBL

1. L'ASBL est-elle assujettie à la TVA en Belgique : entièrement, partiellement (assujettie mixte, prorata), pas du tout ? Cela change le traitement de **toutes** les factures belges : une ASBL non assujettie ne déduit rien et sa TVA est un coût.
2. Si assujettie mixte : le prorata général au niveau de l'entité est-il acceptable (pas de prorata par secteur) ? Régularisation annuelle et révision des immobilisations sur 5 ans (15 pour les immeubles), seuil de 10 points.
3. Franchise de TVA (petite entreprise) : la TVA d'achat va-t-elle bien entièrement en charge non déductible (compte 640400) ?

## 5. TVA étrangère (T12)

Constaté avec une facture zambienne à 16 % : LedgerFlow la comptabilisait comme TVA belge déductible. Traitement actuel `foreign_vat` (cas C16 : aucune ligne de TVA, aucune grille belge, la TVA est incluse dans la charge de la ligne), **décision provisoire** pour tester un projet de bailleur.

1. TVA étrangère récupérable **par remboursement** : quel compte (sous-compte de la classe 41 ?) et comment solder la créance à l'encaissement ? Non codé aujourd'hui.
2. La TVA en charge doit-elle rester **dans la charge de la ligne** (pour l'analytique et le budget) ou être isolée en **640400** ?
3. Une facture étrangère **sans TVA** (exonérée ou fournisseur non assujetti) est-elle traitée correctement comme un achat belge à 0 % ? Sa base apparaît-elle à tort en grilles 81–83 ? Faut-il le traitement `export` (aucune grille) ?
4. La récupérabilité se décide-t-elle par pays, par projet ou facture par facture ? (Choix actuel : par projet.)
5. La TVA non récupérable est-elle une dépense éligible pour les bailleurs ?
6. Un fournisseur d'un autre pays de l'UE qui facture sa TVA locale suit-il la même règle ?

## 6. Mentions légales de la facture (T7)

Les mentions sont **génériques, sans article du Code TVA** (domestique, intracom, autoliquidation, export, franchise). Les factures PDF types par régime ne sont **pas encore jointes** à ce dossier ; elles seront ajoutées dans un second temps.

## 7. Résultat de la validation

| Date | Comptable | Sections validées | Corrections demandées |
|---|---|---|---|
|  |  |  |  |

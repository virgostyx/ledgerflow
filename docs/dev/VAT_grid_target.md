# Tableau cible des grilles TVA (à valider)

Source unique : `docs/dev/notice explicative TVA.pdf` (SPF Finances, **janvier 2014**, ce sont les numéros `n°` cités). Pas de comptable : à recouper avec une notice récente et le XSD officiel (introuvable, seul le v0.7 tiers est connu).

## 1. Ventes (base HT)

| Cas | Grille de base | TVA | Source |
|---|---|---|---|
| Domestique 6 % | **01** | 54 | n° 86, ex. 253 |
| Domestique 12 % | **02** | 54 | n° 86 |
| Domestique 21 % | **03** | 54 | ex. n° 234 (1 033,06 → 216,94) |
| Domestique 0 % / régime particulier (tabac, journaux…) | 00 | aucune | n° 82 |
| Autoliquidation par le client (construction, etc.) | **45** | aucune | n° 101 |
| Intracom livraison de biens (art. 39bis) | 46 | aucune | n° 111 |
| Intracom services B2B (règle générale, client UE assujetti) | **44** | aucune | n° 1002 |
| Export hors UE, autres exonérations (art. 39-42, 44bis) | **47** | aucune | n° 123 |
| Avoir sur 44 ou 46 | **48** (positif) | aucune | n° 134 |
| Avoir sur toute autre vente | **49** (HT) | **64** (TVA de l'avoir) | n° 252-253 |

Règle avoirs ventes : le HT de l'avoir ne diminue **jamais** 01-03 (n° 98) ; il va en 49 ; la TVA de l'avoir va en 64. Un avoir sans TVA : 49 seulement.

## 2. Achats (base HT)

| Cas | Grille de base | TVA due | TVA déductible |
|---|---|---|---|
| Domestique, comptes 600-605 | **81** | | 59 |
| Domestique, comptes 61 (et 64 pour la TVA non déductible) | **82** | | 59 |
| Domestique, classe 2 (20-27, hors 28-29) | **83** | | 59 |
| Intracom biens (acquisition) | 86 | **55** | 59 |
| Intracom services (règle générale) | **88** | **55** | 59 |
| Autres autoliquidations (sous-traitance construction, services à critère dérogatoire, import avec report : hors 57) | **87** | **56** | 59 |
| Import avec report de perception | 87 | **57** | 59 |

Les grilles 81/82/83 ne dépendent PAS du taux, mais de la nature du compte (n° 149-158), avec ou sans TVA. **Les grilles 86/87/88 s'ajoutent à 81-83, elles ne les remplacent pas** (ex. n° 161-2 : acquisition intracom d'une voiture → 83 ET 86 ET 55 ET 59). Le montant en 81-83 est le HT, **majoré de la TVA non déductible** (n° 161), hors part privée (n° 160). Pour une autoliquidation, la TVA non déductible n'est pas reprise en 86/87/88.

Avoirs achats (n° 163, 198, tableau n° 175) :

| Avoir reçu sur… | Déduit de | Inscrit en | TVA de l'avoir |
|---|---|---|---|
| opération 86 ou 88 | 81-83 ET 86/88 (« dans la mesure du possible ») | **84** | aucune ; régularisation TVA en 61/62 (peut être omise si déduction totale et pas d'investissement) |
| opération 87 | 81-83 ET 87 | **85** | idem |
| achat domestique avec TVA | 81-83 | **85** | **63** si elle avait été déduite |
| achat domestique sans TVA sur l'avoir | 81-83 | **85** | aucune |

Plancher à zéro : si la déduction rend la grille négative, on inscrit 0 et le reste se reporte sur la déclaration suivante (n° 163, 198).

## 3. Totaux et solde (calcul)

- **XX** = 54 + 55 + 56 + 57 + 61 + 63
- **YY** = 59 + 62 + 64
- **71** = XX − YY si XX > YY ; **72** = YY − XX si YY > XX ; **une seule** des deux ; si XX = YY, 71 = 0,00 (n° 256-259).
- 66 : jamais remplie. 91 : acompte de décembre (déclarants mensuels), hors périmètre.

## 4. Ce qui change par rapport à l'existant

1. 01 ↔ 03 inversés dans `RATE_TO_GRID` (défaut réel, aujourd'hui).
2. Achats : ventilation par taux → par nature de compte.
3. 48/49 (avoirs, pas construction/export) ; 45 pour la construction ; 44/47 pour les services intracom et l'export.
4. TVA autoliquidée : 55 (86, 88), 56 (87), 57 (import). Aujourd'hui 56 et 57 sont mal attribuées.
5. Achat intracom services : 88 (pas 87).
6. Grilles 63, 64, 84, 85, XX, YY, 71, 72 : à créer.
7. Migration : les `journal_entry_lines.vat_code` déjà postés sont faux (au moins 1↔3 et les achats).

## 5. Points à trancher

- 81-83 : par préfixe de compte (600-605 / 61+64 / 2x) sans nouvelle colonne, ou via `accounting_accounts.vat_code_default` (existe, jamais utilisée). Recommandation : préfixe, plus simple, même règle que la notice.
- Les comptes de charge hors 60/61/64/2x (62, 63, 65…) : pas de grille (n° 154). Une facture avec TVA sur un tel compte sera ignorée des grilles 81-83.
- Import hors UE avec report de perception (grille 57) : pas géré aujourd'hui, à ne pas ajouter tant que l'app n'a pas de régime « import ».
- Grille 00 : la vente à 0 % « ordinaire » n'y va pas ; à décider si elle passe en 47 (exonérée) ou si le taux 0 % reste refusé.

## 6. État d'implémentation (2026-09-26)

Fait : 01↔03 (migration), achats 81/82/83 par compte, autoliquidation 86/87/88 + 55/56, ventes 44/45/47, avoirs (48/49/64 ventes ; 63, 84, 85 achats ; 61/62 pour les avoirs en autoliquidation), régularisation du prorata nette des avoirs.

Limites connues (choix : ne pas les faire au départ) :
- TVA non déductible non ajoutée aux bases 81-83 (n° 161) ; part privée non gérée.
- Plancher à zéro des grilles 81-83/86/88 après avoirs, et report sur la période suivante (n° 163, 198) : une grille peut sortir négative.
- Avoirs sur autoliquidation avec prorata : la régularisation 61/62 porte les montants postés, sans distinguer la part non déductible.
- Avoirs déjà postés avant ce changement : anciennes grilles (négatifs dans 54/59/base), pas de migration.
- Grille 0 pour les ventes exonérées, 57 (import avec report), 91 (acompte), grilles de totaux XX/YY/71/72 : à faire.

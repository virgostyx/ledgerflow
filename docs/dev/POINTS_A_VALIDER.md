# LedgerFlow — Points à faire valider avant un usage réel sans réserve

Document de synthèse créé le 2026-10-20. Il rassemble en un seul endroit les questions ouvertes dispersées dans `docs/dev/**/QUESTIONS.md`, `HANDOFF_next_steps.md`, `DEPLOYMENT_PLAN.md`, `VAT_grid_target.md`, `agent/DATA_PROCESSING.md` et les fiches de capacité (`reports/R*.md`, `features/F*.md`, `signature/B*.md`).

**Ce que ce document est, et n'est pas**
- C'est un **index de décision**, compilé à partir des documents ci-dessus. Le détail et la justification de chaque point restent dans le fichier source indiqué entre crochets.
- Je l'ai fait en relisant les documents, **pas en re-vérifiant le code point par point**. Plusieurs documents datent de semaines différentes : un point listé ici comme « non fait » a pu être traité depuis (c'est notamment possible pour la TVA, §1.1). Avant de transmettre une section à un comptable, il faut vérifier l'état réel dans le code ou dans l'application.
- Les affirmations légales ou réglementaires marquées « *ma compréhension* » viennent de ma mémoire, pas d'une source relue : elles sont là pour orienter la question posée au professionnel, pas pour la trancher.
- Chaque point a une case à cocher et une priorité. Quand un professionnel valide, on coche, on note la date et le nom dans la section « Validations obtenues » (§9), et on met à jour le fichier source.

**Priorités**
- **[P1]** à valider avant de se fier à LedgerFlow pour une vraie comptabilité (cabinet seul, palier 1).
- **[P2]** à valider avant d'activer la fonction concernée, ou avant d'ouvrir à des clients (palier 3).
- **[P3]** confort, optimisation ou décision sans risque comptable.

**Qui doit répondre** : `[C]` comptable ou expert-comptable belge ; `[J]` juriste (droit commercial, RGPD, numérique) ; `[B]` banque ou prestataire externe ; `[V]` vous (décision de produit) ; `[S]` sécurité ou exploitation.

---

## 0. Ma lecture d'ensemble

1. **Le plus gros risque est comptable et fiscal, pas technique.** Le moteur de partie double est protégé en base (déséquilibre impossible, immutabilité, chaîne d'audit). Ce qui n'a jamais été relu par un professionnel, ce sont les **règles** : grilles de TVA, rubriques des comptes annuels, comptes du plan comptable, clôture, textes envoyés aux clients. Un logiciel peut être parfaitement cohérent en interne et déclarer la mauvaise grille.
2. **Cinq blocs concentrent l'essentiel** : (a) la déclaration TVA et ses grilles (§1.1), (b) le plan comptable livré et la clôture (§1.2), (c) les comptes annuels BNB (§1.5), (d) les mentions légales et textes envoyés (§1.1 T7, §1.7), (e) le cadre RGPD/juridique du portail et de l'agent (§2). Si vous ne devez faire valider que cela, vous couvrez la grande majorité du risque.
3. **Beaucoup de fonctions sont éteintes par défaut** (drapeaux de société) et peuvent le rester. Plus on réduit le périmètre activé au démarrage, moins il y a à faire valider (voir §8).
4. **Une question de cadrage change tout** : quelle forme juridique est visée en premier (société commerciale, ASBL, indépendant en personne physique) ? Le modèle de comptes annuels livré est celui des sociétés commerciales ; le plan ASBL n'a pas de comptes 14 ni de réserve légale ; un indépendant en personne physique ne dépose pas à la BNB. Cela décide du contenu des §1.2 et §1.5.

---

## 1. Points comptables et fiscaux `[C]`

### 1.1 TVA et facturation

- [ ] **T1 [P1] Tableau des grilles de TVA.** Le mapping (ventes 01/02/03, 44–49 ; achats 81/82/83, 86/87/88 ; TVA 54/55/56/57/59, 61–64 ; solde 71/72) a été reconstruit d'après la **notice explicative du SPF Finances de janvier 2014**, sans comptable. Le mapping est maintenant en base (`accounting_vat_codes`, `…_grid_mappings`, `…_account_grid_rules`), donc corrigeable sans code. À faire : relecture ligne par ligne du tableau cible, et recoupement avec la notice en vigueur. *Source : `VAT_grid_target.md`, `reports/QUESTIONS.md` § R09/R10.*
  - **Reco** : donner au comptable une page avec le tableau et **10 à 15 cas chiffrés** (facture, avoir, intracom, autoliquidation, prorata) avec la déclaration que LedgerFlow produit ; il compare à ce qu'il déclarerait. C'est plus rapide et plus fiable qu'une relecture abstraite.
- [ ] **T2 [P1] XSD Intervat.** Le XML de déclaration est validé contre un XSD **v0.7 de 2012, copie tierce** (dépôt lino-framework), pas contre le XSD officiel courant. Un fichier valide contre l'ancien schéma peut être refusé par MyMinfin. Il faut obtenir le XSD officiel (inscription développeur MyMinfin) ou, à défaut, faire tester un fichier réel par le comptable avant tout dépôt. Un guide d'intégration Intervat est dans `docs/dev/guide_integration_api_intervat.pdf` : je n'ai pas vérifié s'il a été exploité. `[C][B]`
  - **Reco** : tant que ce point n'est pas levé, ne **jamais** déposer le XML tel quel ; le saisir dans Intervat à la main à partir des grilles affichées.
- [ ] **T3 [P1] Limites connues de la déclaration** (à re-vérifier dans le code, certaines peuvent être faites) : TVA non déductible non ajoutée aux bases 81–83 (notice n°161) ; part privée non gérée (n°160) ; plancher à zéro des grilles et report sur la période suivante (n°163, 198) ; grille 00 / vente à 0 % « ordinaire » ; grille 57 (import avec report de perception) et 91 (acompte de décembre) non gérées ; avoirs postés **avant** le changement de mapping non migrés ; déclarations déjà générées avec d'anciennes grilles à régénérer. *Source : `HANDOFF_next_steps.md` #2, `VAT_grid_target.md` §6.*
- [ ] **T4 [P1] Période de TVA déposée = période verrouillée.** Conformément à la spec, un paiement ou un rapprochement bancaire daté dans une période déjà déposée est refusé. Est-ce le bon comportement pratique, ou faut-il une régularisation dans la période suivante ? Le marqueur `journal_entries.vat_regularisation` est posé sur les extournes déplacées mais **R09 ne le lit pas encore**. `[C][V]` *Source : `features/QUESTIONS.md` § F01, § F07.*
- [ ] **T5 [P2] Prorata et assujetti mixte.** Prorata au niveau de la société (pas par code TVA), régularisation annuelle, révision des immobilisations sur 5 ans (15 pour les immeubles) avec un seuil de 10 points. Les textes d'aide ne citent aucun article du Code TVA. Faire valider les règles et les textes. *Source : `HANDOFF_next_steps.md` #9.*
- [ ] **T6 [P2] Franchise de TVA.** Saisie HT + TVA conservée pour les achats ; toute la TVA d'achat va en charge non déductible sur **640400** (pas dans le compte de charge lui-même) ; seules les opérations nationales sont gérées. Est-ce la présentation attendue ? *Source : `HANDOFF_next_steps.md` #10.*
- [ ] **T7 [P1] Mentions légales de la facture PDF et des e-mails.** Les mentions par régime (domestique, intracom, autoliquidation, export, franchise) sont **génériques, sans article du Code TVA**. Une facture sans la bonne mention est une non-conformité visible du client. À faire valider avec une facture type par régime. *Source : `HANDOFF_next_steps.md` #3a, #9.*
- [ ] **T8 [P2] Listings.** Listing intracommunautaire trimestriel ; listing annuel des clients assujettis (R10) : seuil de **250 € HT** (valeur de la spec, à valider), « assujetti » déduit de la présence d'un numéro de TVA (pas de champ dédié). *Source : `reports/R09.md`.*
- [ ] **T9 [P2] Peppol, catégories de TVA des factures reçues.** E (exonéré) et O (hors champ) sont traités comme un achat ordinaire à 0 % ; AE, K et G (autoliquidation, intracom, export) **ne sont pas mappées** : un document qui en porte une attend une décision. Une facture négative est mise en révision, jamais brouillonnée. *Source : `features/QUESTIONS.md` § F06 étape 3.*
- [ ] **T10 [P2] Avoirs.** Remboursement d'un avoir sur une facture déjà encaissée : flux non conçu (l'avoir reste non imputé). Grilles 48/49 (ventes) et 85 (achats) à confirmer. *Source : `HANDOFF_next_steps.md` #1.*
- [ ] **T11 [P3] TVA des écritures importées.** Les écritures importées par F13 ou l'API n'ont pas de code TVA lu par la déclaration : seules les factures portent la TVA. À savoir pour toute reprise d'historique.
- [ ] **T12 [P1] TVA étrangère (fournisseur hors Belgique dont la facture porte la TVA de son pays).** Constaté le 2026-10-28 avec une facture zambienne (16 %) : LedgerFlow la comptabilisait comme **TVA belge déductible** (grille 59), ce qui gonfle la déclaration belge. Règles décrites par le propriétaire du produit :
  - projet UE en Zambie : la TVA est **exonérée sur demande préalable** ; la facture est encodée **sans TVA** dans BudgetFlow ;
  - si l'exonération n'est pas possible pour une facture, la facture est encodée **avec** la TVA, qui est une **charge** ;
  - fournisseur non assujetti (chiffre d'affaires sous un plafond) : facture **sans TVA** ;
  - autres pays : la TVA est **récupérable ou non** ; récupérable soit par **remboursement** (alors elle doit aller sur un compte **« TVA étrangère à récupérer »**), soit par **exonération préalable** comme en Zambie.

  **Fait (2026-10-28)** : le traitement `foreign_vat` de LedgerFlow (achats seulement) met la TVA **dans la charge de la ligne** (donc dans ses comptes analytiques et ses postes budgétaires), sans ligne de TVA ni grille de la déclaration belge ; le fournisseur est dû pour le total. BudgetFlow l'envoie quand le fournisseur n'est pas belge et que la facture porte de la TVA ; sans TVA, rien n'est envoyé.

  **Pas fait** : TVA récupérable par remboursement (compte de créance), et le choix par pays, par projet ou par facture.

  **Décisions provisoires (2026-10-31, sans comptable, pour tester PRODEM et faire une démonstration ; à faire valider avant toute mise en production réelle)** :
  - La TVA étrangère non récupérable reste **dans la charge de la ligne** (coût d'acquisition), pas sur 640400.
  - La TVA étrangère **récupérable par remboursement** n'est pas codée (pas de créance « TVA étrangère à récupérer ») : pour PRODEM, exonération préalable (facture sans TVA) ou TVA en charge.
  - La récupérabilité se décide **par projet** (case « VAT is a cost of this project » ; sans TVA encodée = exonérée).
  - Un fournisseur **hors UE sans TVA** reçoit lui aussi `foreign_vat` : aucune ligne de TVA, aucune grille belge. Un fournisseur d'un autre pays de l'UE sans TVA ne reçoit rien (autoliquidation, traitement à valider).
  - L'entité de test est supposée **assujettie, TVA belge déductible** (numéro de TVA fictif à sa création). Une ASBL réellement non assujettie ne déduit rien : sa TVA belge serait aussi un coût.
  - Les bailleurs : la TVA n'est éligible que si elle est définitivement supportée ; à confirmer avec chacun.

  **Questions pour le comptable** :
  1. Pour la TVA étrangère récupérable par remboursement : quel compte exactement (sous-compte de la classe 41 ?), et comment solder la créance à l'encaissement du remboursement ?
  2. La TVA en charge doit-elle rester **dans la charge de la ligne** (choix actuel, pour que l'analytique et le budget la portent) ou être isolée sur le compte **640400** comme pour la franchise (T6), au prix de sortir ce montant de l'analytique ?
  3. Une facture étrangère **sans TVA** (exonérée ou fournisseur non assujetti) est aujourd'hui traitée comme un achat belge à 0 % : sa base apparaît-elle à tort dans une grille 81–83 de la déclaration belge ? Faut-il lui donner le traitement `export` (aucune grille, aucune TVA auto-liquidée) ?
  4. Où se décide la récupérabilité : par pays, par projet, ou facture par facture ?
  5. La TVA non récupérable est-elle une dépense éligible pour les bailleurs concernés ?
  6. L'entité est-elle assujettie à la TVA en Belgique (entièrement, partiellement, pas du tout) ? Cela change aussi le traitement des factures belges.
  7. Les fournisseurs de l'UE (hors Belgique) qui facturent leur TVA locale suivent-ils la même règle ?

### 1.2 Plan comptable (PCMN) et clôture

- [ ] **C1 [P1] Relecture du PCMN livré** (`db/seeds/pcmn_commercial.json`, `pcmn_asbl.json`). Jamais relu par un comptable. Écart déjà connu : « Produits acquis » est en **490200** et « Produits à reporter » en **492200**, alors que le PCMN officiel les place en **491** et **493** ; R17 suit les libellés du plan livré. **À trancher** : corriger le seed et migrer les données, ou garder. *Source : `reports/QUESTIONS.md` § R17.*
  - **Reco** : faire relire le plan complet (pas seulement ce point) ; si le comptable confirme 491/493, corriger tant que la base contient peu de données réelles.
- [ ] **C2 [P1] Comptes de clôture et de report.** Résultat **699000** ; report du résultat sur **140100 / 140200** (décidé le 2026-10-05, 130000 « Réserves » n'est plus le défaut) ; pour une ASBL **120100 / 120200**. Sociétés existantes : réglage à basculer par `bin/rails closing:use_retained_earnings_accounts` (non automatique) ; ce qui est déjà reporté sur 130000 y reste. Faire valider ces comptes. *Source : `features/QUESTIONS.md` § F10.*
- [ ] **C3 [P1] Affectation du résultat.** Seule la **réserve légale** est gérée (5 % du bénéfice de l'exercice, plafond 10 % du capital souscrit). Base exacte à valider (avant ou après perte reportée ; capital libéré ou non ; le capital est lu comme le solde créditeur des comptes 100…). Dividendes, autres réserves et précompte mobilier : **non gérés**, à faire à la main. L'affectation ne s'applique pas à une ASBL. *Source : idem.*
- [ ] **C4 [P1] Écritures de clôture et à-nouveaux.** Ordre des étapes, reprise ligne par ligne des créances et dettes avec échéance conservée, étape 11 (comptes **499000 et 580000** à zéro), report à nouveau sur un exercice non clôturé (refusé si déséquilibré), premier exercice de durée différente de 12 mois (avertissement sans adaptation des seuils). Un cycle complet de clôture sur une vraie société doit être relu par le comptable. *Source : `features/QUESTIONS.md` § F10, `HANDOFF_next_steps.md` #5.*
- [ ] **C5 [P1] Réductions de valeur et provisions.** Les créances de plus de 90 jours sont signalées (avertissement) mais la réduction de valeur (631xxx) et les provisions sont **entièrement manuelles**. Règle de seuil à valider ; faut-il un assistant ? `[C][V]`
- [ ] **C6 [P2] Régularisations (R17).** Charges à imputer / produits acquis = total du service × jours écoulés ÷ jours de la période ; écritures générées en **brouillon**. Formule à valider (prorata au jour, pas au mois).
- [ ] **C7 [P1] Extournes et rapports.** Règle retenue : une écriture extournée **reste une écriture validée du grand livre** ; elle et son extourne comptent toutes deux (balance, grand livre, R04/R05, journal, trésorerie, KPI). Exceptions voulues : TVA, analytique et projets restent sur les seules écritures `posted`. Date d'une extourne dans une période verrouillée : lendemain du dernier verrou. À valider. *Source : `features/QUESTIONS.md` § F07.*
- [ ] **C8 [P2] Comptes techniques à confirmer** : **658100 / 758100** (arrondis de paiement et de lettrage), **580000** (virements internes), **651200 / 751100** (écarts de change, que la spec cite en 654 / 754), **499100 / 499200** (écarts de conversion), **660100 / 760100** (moins-values de cession, prix de vente). *Source : `features/QUESTIONS.md` § F02, F04, F11, `HANDOFF_next_steps.md` #4b.*
- [ ] **C9 [P2] Verrouillage et quatre yeux.** Le lettrage reste possible dans une période verrouillée ; le délettrage d'une telle ligne devrait exiger `reconciliations.unreconcile_locked` (pas encore le cas) ; quatre yeux limité aux écritures saisies à la main (pas aux factures). `[C][V]`

### 1.3 Devises et écarts de change

- [ ] **D1 [P1 si devises, sinon P3] Traitement des écarts de change latents.** Décidé le 2026-10-01 : **perte latente comptabilisée** (651200 / 499100, brouillon, extourne au lendemain), **gain latent non comptabilisé** par défaut ; options « différer » (499200) ou « comptabiliser » par société. À faire valider par le comptable : comptes, extourne, traitement des paiements partiels (le prorata suppose le même taux sur toute la ligne), **politique par société**. *Source : `features/QUESTIONS.md` § F11, `reports/QUESTIONS.md`.*
- [ ] **D2 [P2] Sources et politique de taux.** BCE (taux du jour), InforEuro (moyenne mensuelle), taux de clôture, saisie manuelle. Pas de repli silencieux ; repli de 7 jours par devise si activé. Écart de plus de 5 % avec l'officiel : avertissement seulement. Le **kwacha zambien (ZMW) n'existe que par InforEuro** : choisir la bonne politique pour les bailleurs. Les imports automatiques n'ont jamais tourné sur le vrai réseau. `[C][V]`
- [ ] **D3 [P2] Arrondi et décimales.** Conversion ligne par ligne, écart d'arrondi (≤ 0,02) sur 651200/751100 ; tolérance de validation ramenée à 0,005 ; décimales de devise contrôlées sur les lignes, pas sur la banque.

### 1.4 Immobilisations et amortissements

- [ ] **I1 [P1 si immobilisations] Méthode d'amortissement.** Linéaire annuel, prorata au mois à partir du mois de mise en service ; un bien cédé est amorti jusqu'au mois de cession **inclus**. **Amortissement comptable et fiscal ne sont pas distingués.** Dégressif non codé (conditions légales belges à faire valider avant de coder). Réductions de valeur hors périmètre. *Source : `HANDOFF_next_steps.md` #4.*
- [ ] **I2 [P2] Cession.** Présentation brute : la VNC sortie va en **660100**, le prix de vente est comptabilisé par une facture client sur **760100** ; pas de moins-value calculée, pas de cession partielle, pas d'annulation d'une cession. À valider ou à faire évoluer.

### 1.5 Comptes annuels (BNB)

- [ ] **A1 [P1] Table de correspondance rubriques/comptes.** `config/annual_accounts/company_abridged.yml` a été **écrite de mémoire d'après le schéma BNB, jamais validée** par un comptable ni contre le modèle officiel. Des erreurs ont déjà été trouvées en testant (compte 499000 sans rubrique). **À valider intégralement avant tout dépôt réel.** `[C]`
  - **Reco** : tant que ce n'est pas fait, présenter la sortie comme « projet de comptes annuels » et ne rien déposer à la BNB depuis LedgerFlow.
- [ ] **A2 [P1] Périmètre du modèle.** Seul le **modèle abrégé des sociétés commerciales** existe. Absents : modèle micro, modèle complet, schéma des ASBL (autre table), annexes, dépôt XBRL / saisie BNB, PDF. Un indépendant en personne physique ne dépose pas à la BNB. Comptes 130000 affichés avec la rubrique 14 ; classes 0, 69, 79 ignorées ; 699000 exclu. `[C][V]`
- [ ] **A3 [P2] Simplifications connues.** Un solde débiteur sur un compte de dettes (ex. 44) réduit la rubrique de dettes au lieu d'apparaître en créances (rubrique négative possible) ; `reclassify_contra_balances` non fait. Le contrôle C13 de R19 **n'attrape pas un compte de produits sans rubrique**. *Source : `reports/QUESTIONS.md` § R07/R08, `agent/QUESTIONS.md` § A08.*
- [ ] **A4 [P3] Deuxième modèle « présentation de gestion » (EBITDA)** et vues trimestrielles : reportés.

### 1.6 Banque, rapprochement et lettrage

- [ ] **L1 [P2] Tolérance d'arrondi des paiements** (0,05 € par défaut, recettes seulement, comptes 658100/758100 créés à la main par le propriétaire). Valider le principe, les comptes et le seuil unique clients/fournisseurs. *Source : `features/QUESTIONS.md` § F02, F04.*
- [ ] **L2 [P2] Règles de lettrage assisté.** « Même référence » = référence d'écriture, numéro et référence fournisseur de la facture, communication structurée (4 caractères minimum, sans casse ni ponctuation) ; score 100 = jamais une devinette ; règle 6 (écart d'arrondi) en brouillon dans le journal divers ; lettrage automatique éteint par défaut. À valider avec un comptable : sources de référence, seuils, usage de 758100 en achats.
- [ ] **L3 [P2] Règles de société « Book a draft »** : brouillon créé dès l'import, sans confirmation, même sous 100 €. À confirmer pour les montants importants. Virements internes (580000) : fenêtre de 3 jours et IBAN exigé.
- [ ] **L4 [P2] Paiements fournisseurs et notes de crédit.** Un paiement par fournisseur ; compensation des notes de crédit **seulement contre le paiement groupé** ; si les notes couvrent tout, aucun paiement et lettrage manuel ; comptabilisation du paiement en **brouillon** à la confirmation du débit ; double paiement probable → facture en litige mais écriture validée. À faire relire par le comptable sur un cas réel. *Source : `signature/QUESTIONS.md` § B01b, B01c.*
- [ ] **L5 [P3] R06 (rapprochement bancaire).** Sans relevé, calcul « plat » ; le lien transaction ↔ écriture est supposé exister à la date demandée s'il existe aujourd'hui (pas de date « lié le »). Approximation à connaître.

### 1.7 Relances clients, intérêts de retard

- [ ] **R1 [P1 si relances] Textes des relances (fr, nl, en).** Rédigés par moi, jamais relus. Le niveau 3 (« mise en demeure ») est générique, sans délai chiffré ni article de loi, **pas un avis juridique**. À faire relire par un comptable et un juriste (`[J]` pour le niveau 3). *Source : `features/QUESTIONS.md` § F09.*
- [ ] **R2 [P1 si intérêts] Intérêts de retard et indemnité.** Désactivés par défaut, **aucun taux ni montant dans le code**. Si activés : intérêt simple, année de 365 jours, indemnité fixe, frais par niveau ; formule choisie par moi, à faire valider ; non comptabilisés. *Ma compréhension* : le taux légal pour les transactions commerciales est fixé par la loi du 2 août 2002 et publié périodiquement ; à confirmer avec le professionnel.
- [ ] **R3 [P3] Ancien module de relances** conservé (historique séparé, non converti en campagnes). Convertir ou garder les deux ?
- [ ] **R4 [P2] Délai minimum entre relances (14 jours)**, niveaux (7, 21, 45 jours), seuil appliqué au total du client : ajouts à la spec à valider.

### 1.8 Documents et conservation

- [ ] **K1 [P1] Durée de conservation.** Fixée à **10 ans à partir du dépôt** pour tous les types. À valider : durée par type, point de départ (dépôt ou clôture de l'exercice de l'écriture liée), suspension légale. *Ma compréhension* : le Code TVA impose 10 ans pour les factures et le droit comptable 7 ans pour les livres et pièces ; **à confirmer** et à distinguer par type. Les messages du portail sont aussi à 10 ans, sans purge codée. `[C][J]` *Source : `features/QUESTIONS.md` § F03, `signature/QUESTIONS.md` § B02c.*
- [ ] **K2 [P2] Aucune suppression avant le terme**, même pour un dépôt par erreur (archivage seulement). Confirmer, ou autoriser une correction dans les N minutes.
- [ ] **K3 [P2] Extraction de documents.** Propositions seulement, rien d'appliqué sans confirmation ; le brouillon de facture utilise la valeur confirmée, à défaut la proposée ; doublon = même fournisseur + même numéro. Faut-il exiger la confirmation de numéro, date et total avant brouillon ?

### 1.9 Consolidation (F12), à n'activer que sur besoin

- [ ] **G1 [P3, P1 si utilisée]** Aucune règle de consolidation n'est appliquée sans **validation d'un comptable enregistrée** dans l'application. À valider si un groupe est consolidé : éliminations créances/dettes (40/41 ↔ 42/48, 29 ↔ 17), ventes/achats (70 ↔ 61), intérêts minoritaires, mise en équivalence, conversion de devise, rubrique de l'écart de conversion. Les valeurs proposées sont **ma proposition, pas un choix validé**. *Source : `features/QUESTIONS.md` § F12.*
  - **Reco** : laisser le drapeau `f12` éteint tant qu'aucun groupe réel n'est à consolider.

### 1.10 Agent IA (A01–A12), à n'activer qu'après relecture

- [ ] **IA1 [P1 si agent actif] Protocoles d'explication d'anomalies.** Les 22 protocoles (`app/services/agent/playbooks/`) sont des **premiers jets non validés** ; priorité de relecture : C04, I5, I7, puis C09, C14, C16, C17. D'ici là, l'agent présente les causes comme des hypothèses.
- [ ] **IA2 [P1] Jeu d'évaluation.** 30 cas et leurs « attendus », dont les écritures de référence (loyer 610100, assurance 610400, carburant 613300, repas 617300, ordinateur 240200, note de crédit 614100, TVA 410100), **jamais relus par un comptable**. Points douteux : assurance annuelle en charge ou à reporter, déductibilité du carburant, grilles de TVA des immobilisations et avoirs. La mesure à 90 % n'a aucun sens avant relecture.
- [ ] **IA3 [P1] Base de connaissances.** Aucun document réel livré ; les 11 notes d'évaluation sont inventées et n'énoncent pas le droit belge. Qui charge et relit le PCMN et les fiches, sous quelle licence ? Chaque document doit être relu par le comptable référent avant mise en service. Recommandation : exiger les quatre yeux pour la base.
- [ ] **IA4 [P2] Politique de relance de l'agent** (niveau 3 parle de « démarches de recouvrement ») ; seuil de revue renforcée 5 000 € ; péremption des propositions 7 jours ; tolérance TVA 0,05 €.

### 1.11 Reprise de données

- [ ] **O1 [P1 avant migration d'une vraie société] Import des soldes d'ouverture et des factures ouvertes** (CSV) : premier exercice seulement, EUR, début d'exercice, compte d'attente 499000 qui doit être soldé, un seul import, **non vérifié sur un vrai export**. Faire un essai complet avec le comptable sur une balance réelle, et comparer. *Source : `HANDOFF_next_steps.md` P3.*
- [ ] **O2 [P1] Cycle complet réel** (facture, avoir, TVA, clôture) validé par un comptable belge : sans cela, ne pas parler de produit « prêt ». *Source : `HANDOFF_next_steps.md` P3.*

---

## 2. Points juridiques, RGPD et valeur probante `[J]`

- [ ] **J1 [P2, bloquant pour le palier 3] Texte de validation des comptes par le client** (`Portal::ApprovalText`, version `2026-10-draft-1`, fr/nl/en). Dit que la validation n'est ni une signature électronique qualifiée ni l'approbation par l'assemblée générale. **Aucune formulation relue par un juriste** ; traduction néerlandaise à relire par un néerlandophone. Le texte affiché et son SHA-256 sont consignés avec chaque preuve.
- [ ] **J2 [P2] Conditions d'utilisation du portail et déclaration de confidentialité** : n'existent pas. À fournir avant la première invitation réelle.
- [ ] **J3 [P2] Conformité RGPD de l'ensemble.** Registre des traitements (documents clients), mentions d'information, procédure d'incident, **contrats de sous-traitance** (courriel Hostinger, stockage OVH, horodatage, fournisseur de modèle). *Source : `DEPLOYMENT_PLAN.md` §9.*
- [ ] **J4 [P1 si agent actif] Agent IA : traitement des données.** Huit questions ouvertes (`agent/DATA_PROCESSING.md`) : conservation chez le fournisseur, usage pour l'entraînement, région et transferts hors UE, sous-traitants, **secret professionnel du cabinet**, base légale et information des personnes, analyse d'impact (AIPD), texte de consentement (`app/views/agent/settings/_consent.html.erb`). Tant qu'elles ne sont pas tranchées, l'agent doit rester éteint. Le mode `full_document` (envoi du fichier brut) n'existe pas et ne doit pas être créé sans accord explicite.
- [ ] **J5 [P2] Conservation contre droit à l'effacement.** Messages du portail et documents conservés 10 ans, aucune purge codée ; l'agent garde 90 jours par défaut (30/90/365). Comment articuler obligation de conservation et effacement d'une personne ? Les notes de dossier ne sont pas couvertes par l'export/effacement (nom retrouvé par comparaison de texte seulement).
- [ ] **J6 [P2] Valeur probante des certificats d'intégrité.** Signature Ed25519 (clé créée, publiée et sauvegardée, voir dernier commit) ; **aucun horodatage externe** au palier 1 (le certificat dit « No external timestamp ») ; cryptographie maison exclue, bibliothèques standard seulement. Si une valeur juridique est visée : prestataire d'horodatage **qualifié eIDAS** à choisir. À ne pas présenter comme une signature qualifiée. `[J][V]`
- [ ] **J7 [P2] Secret professionnel et déontologie.** Un cabinet peut-il utiliser LedgerFlow, un hébergeur et un fournisseur d'IA pour des données clients, et à quelles conditions ? *Ma compréhension* : question déontologique propre à la profession, à poser à l'institut ou au conseil du propriétaire.
- [ ] **J8 [P2] Textes envoyés aux tiers** : relances (R1), e-mails de facture, courriels aux clients du portail. Aucun texte juridique n'est supposé dans le code ; tous sont de moi.
- [ ] **J9 [P3] Responsabilité et cadre contractuel** si LedgerFlow est un jour proposé à des tiers : conditions générales, responsabilité, assurance. Rien dans le dépôt ; à traiter avant toute offre. *(Reco de ma part, pas dans les documents sources.)*

---

## 3. Banques et prestataires externes `[B]`

- [ ] **X1 [P1 avant le premier vrai paiement] Crelan : format et CODA.** Version de pain.001 acceptée **non connue** (profil `pain.001.001.03` marqué **non vérifié**) ; aucun CODA réel vu. Pour lever la réserve : un CODA réel d'un lot de deux paiements au moins (anonymisé), la version acceptée, idéalement un rejet. Premiers lots : **un seul paiement de faible montant**, comparé à la banque. Le critère « 90 % reconnus, zéro faux positif » est **non démontré**. Rappel : LedgerFlow n'initie jamais de paiement ; l'humain signe dans la banque. *Source : `signature/QUESTIONS.md` § B01b.*
- [ ] **X2 [P1] Fichiers CODA réels.** Le parseur est testé sur des fichiers **fabriqués** conformes à la norme Febelfin v2.8. Déposer 2 ou 3 fichiers anonymisés de vraies banques dans `spec/fixtures/files/coda/`. Détection d'encodage (CP850 / ISO-8859-1), écart de totaux de l'enregistrement 9 (simple avertissement), globalisation (détail non importé) à confirmer.
- [ ] **X3 [P2] Fichier pain.001.** Heure de création écrite sans fuseau ; communication structurée écrite sous forme imprimée dans le champ libre (le champ structuré n'est pas utilisé) ; jours fermés (TARGET) à compléter par banque. À confirmer avec le premier fichier d'essai de **chaque** banque.
- [ ] **X4 [P2] B2Brouter : réception réelle jamais vue.** Le sandbox ne simule pas la réception ; le contenu exact du webhook `received_invoice.created` est écrit d'après la documentation. La première vraie facture reçue est le vrai test. Le **secret de signature des webhooks** reste à renseigner par société. Tolérance de signature de 5 minutes. Forfait gratuit : 24 transactions par an.
- [ ] **X5 [P2] Peppol : schematron officiel non branché.** `Peppol::UblRules` est un sous-ensemble écrit à la main ; un document qui les passe n'est **pas certifié** conforme. Décision en attente : brancher le vrai schematron. Adaptateur Digiteal écrit de mémoire, **non validé**. Schéma `0208` pour les numéros de TVA belges à faire valider. *Ma compréhension* : le B2B électronique via Peppol est devenu obligatoire en Belgique en 2026 ; à confirmer, car cela change l'urgence de X4 et X5.
- [ ] **X6 [P2] Antivirus.** ClamAV recommandé en conteneur accessoire ; sans commande configurée **tout passe**. À installer et tester avant d'ouvrir le dépôt à un client.
- [ ] **X7 [P2] Courriel entrant.** Dépôt par e-mail : exige SPF **et** DKIM certifiés par notre propre serveur de réception (`MAIL_AUTHSERV_ID`) ; sans cette variable, tout va en quarantaine. Port 25 et serveur entrant à décider avec l'hébergeur.
- [ ] **X8 [P2] Horodatage RFC 3161.** Aucune autorité par défaut ; à choisir (J6).

---

## 4. Décisions de produit qui vous reviennent `[V]`

Sans risque comptable direct ; ma recommandation est en tête de chaque ligne.

- [ ] **V1** Perte de l'application d'authentification : **réinitialisation par un propriétaire + codes de secours TOTP** (aujourd'hui aucune procédure en libre-service). *[P1 : un propriétaire qui perd son TOTP est bloqué.]*
- [ ] **V2** Personne avec passkey seulement : écran de ré-authentification par passkey à construire avant d'ouvrir à de vrais approbateurs.
- [ ] **V3** Clés d'API émises avant F01 (sans propriétaire) : **les migrer en leur attribuant un propriétaire**, puis refuser les clés sans propriétaire. JWT historique de BudgetFlow : fixer une **date de suppression** (aucune modification de BudgetFlow sans votre accord).
- [ ] **V4** Quatre yeux sur la **validation d'une facture** (auteur du brouillon ≠ valideur) : recommandé si plusieurs personnes saisissent.
- [ ] **V5** Assistant : lui ouvrir le paiement fournisseur en brouillon ? Rôles personnalisés : réserver aux propriétaires `periods.unlock`, `fiscal_years.manage`, `documents.delete_expired` (**recommandé**) et `agent.configure`, `agent.conversations.review`.
- [ ] **V6** Restriction par journal : filtrer aussi les rapports et le drill-down ? Chantier large ; ne le faire que si un besoin réel existe.
- [ ] **V7** Approbation d'un lot de paiement : sans politique applicable, la demande est **refusée** ; préférez-vous une règle implicite (tout comptable ou propriétaire autre que le préparateur) ? Le propriétaire de la société peut aussi fixer les seuils (`step_up_threshold`, `bulk_threshold`).
- [ ] **V8** Notifications push (service worker, clés VAPID, gem) : non pour l'instant ; le résumé quotidien par e-mail les remplace.
- [ ] **V9** Fuseau horaire de société (l'application tourne en UTC) ; langues : **fr et nl** non faits pour la plupart des écrans (anglais seulement), traductions néerlandaises de ma main à relire.
- [ ] **V10** Budget mensuel et quotas de l'agent (20 questions/h, 100/jour, 40 documents/h) : à fixer après un pilote. Exécution nocturne du mode réel d'évaluation : à décider avec le budget.
- [ ] **V11** `rswag` : non ajouté, l'OpenAPI est générée du code et testée (validé le 2026-10-05) ; `/api/v1/entries` comme voie d'écriture de l'API publique ; durées de F13 (7 jours, 1 heure, 24 h, 8 tentatives, 10 échecs).
- [ ] **V12** Heures calmes des rappels (20 h – 8 h Bruxelles), rétention des messages, quotas du portail : globaux pour l'instant, pas par société.
- [x] **V13** Bandeau « non validé par un comptable » sur les déclarations TVA et les comptes annuels : **fait** (voir §7.6). Il disparaît quand la validation est enregistrée ; ne l'enregistrer qu'après T1/T2 (TVA) et A1 (comptes annuels).
- [ ] **V14** Module comptable de **BudgetFlow** (journaux, plan comptable, écran des factures du comptable) : le comptable travaille dans LedgerFlow seulement, donc il ne sert presque plus aux entités en mode LedgerFlow. **Ne pas le supprimer maintenant** : Dolibarr, WinBooks et l'adaptateur nul l'utilisent encore, et il porte la ré-analyse IA, l'annulation d'un doublon et la mise en litige, qui n'existent pas ailleurs. Ordre recommandé : (1) après le test BudgetFlow ↔ LedgerFlow, lister ce qui manquerait au chef de projet et le déplacer vers l'écran du projet ; (2) masquer journaux et plan comptable pour les entités LedgerFlow (seule partie sûre à retirer) ; (3) ne supprimer le module que si Dolibarr et WinBooks sont abandonnés. *(Modification de BudgetFlow : votre accord explicite.)*
- [ ] **V15** Correction d'une facture **après sa validation** dans BudgetFlow (constaté pendant le test du 2026-10-25) : BudgetFlow interdit toute modification d'une facture validée ou exportée ; le seul recours du chef de projet est « Dispute », qui change le statut dans BudgetFlow **sans prévenir LedgerFlow** (`DisputeOrganizer` ne fait que passer la facture à `disputed`). Résultat : une facture en litige dans BudgetFlow reste comptabilisée dans LedgerFlow. Aujourd'hui, la seule vraie correction passe par le comptable (« Return to project manager » dans LedgerFlow, qui ramène la facture en brouillon dans BudgetFlow). Pistes : (a) « Dispute » prévient LedgerFlow (message ou signalement au comptable, sans extourner automatiquement) ; (b) un champ « demande de correction » avec motif, vu dans la file « from BudgetFlow » ; (c) ne rien changer et le documenter pour les chefs de projet. *(Modification de BudgetFlow et de l'API : votre accord explicite.)*
- [x] **V16** Motif du retour au chef de projet (test du 2026-10-25) : quand le comptable utilise « Return to project manager » dans LedgerFlow, BudgetFlow remet la facture en brouillon avec le motif, mais ne l'affichait que dans la fiche du **module comptable** ; le chef de projet ne le voyait que dans l'e-mail. **Corrigé** : le même bandeau s'affiche sur la fiche de la facture du chef de projet. Reste à décider avec V14 si l'écran comptable de BudgetFlow doit survivre. Le retour n'est pas instantané : jusqu'à 5 minutes (synchronisation toutes les 5 minutes).
- [ ] **V17** TVA reconstituée par BudgetFlow : l'adaptateur ne transmet pas le montant de TVA d'une facture sans lignes mais un **taux déduit** (TVA ÷ montant, deux décimales) ; LedgerFlow recalcule la TVA depuis ce taux. Constaté le 2026-10-27 : 1000,00 € avec 123,45 € de TVA arrive à 12,35 %, soit 123,50 € (écart de 0,05 €), comptabilisé sans erreur, la TVA étant regroupée par taux tronqué (« Recoverable VAT 12% »). Effet : TVA déclarable et dette fournisseur de quelques centimes au-dessus de la facture, un virement exact laisse un solde ouvert à régler par une écriture d'arrondi. Pistes : (a) **accepter** (écarts de centimes, arrondi par le comptable) ; (b) envoyer le **montant de TVA exact** par ligne, que LedgerFlow respecterait (évolution des deux côtés) ; (c) ne rien faire si les factures réelles ont des taux ronds (16 % en Zambie), à vérifier sur un échantillon de PRODEM. À trancher avec le comptable (cf. T1/T2). *(Modification de BudgetFlow et de l'API : votre accord explicite.)*

---

## 5. Sécurité et exploitation `[S]`

- [ ] **S1 [P2, bloquant palier 3] Test d'intrusion externe** couvrant fichiers téléversés, réponses, messages, approbations, courriel entrant, rôle PostgreSQL restreint du portail.
- [ ] **S2 [P2, bloquant palier 3] Revue externe de la cryptographie** de B03c (couvre aussi les preuves d'approbation B02c) : canonicalisation RFC 8785, Ed25519, chaîne de hachage, ancrage, `ledger-verify`.
- [ ] **S3 [P2] Accessibilité et performance sur vrais téléphones** d'entrée de gamme (aujourd'hui Chrome émulé seulement) ; seuils de qualité photo (flou, luminosité) non étalonnés.
- [ ] **S4 [P2] Brakeman** : 34 avertissements antérieurs (4 de confiance haute jugés faux positifs), reste rouge. Traitement différé.
- [ ] **S5 [P1] Exercice de restauration** trimestriel à planifier et noter ; **RPO/RTO** à fixer (défaut : 24 h avec la sauvegarde nocturne ; archivage WAL si moins). Sauvegarde hors serveur et supervision sont en place (derniers commits) ; la restauration complète d'après la copie chiffrée est à éprouver. Conservation des sauvegardes (7 ans ?) à décider avec le comptable.
- [ ] **S6 [P2] Rotation des clés de signature** : manuelle, sans rappel ; procédure de compromission écrite mais jamais jouée.
- [ ] **S7 [P2] Environnement de recette** (staging) avant le palier 2.
- [ ] **S8 [P2] Performance à volume réel.** R02 sans pagination (à corriger avant des comptes à des milliers de lignes) ; R01 sans pagination au-delà de 5 000 comptes ; étape 16 de la clôture lit R05 en entier ; export en tâche de fond au-delà de 10 000 lignes non fait. Tests de volume faits sur jeux synthétiques seulement.
- [ ] **S9 [P3] Interrupteur d'urgence de l'agent** : variable d'environnement relue à chaque requête, effective « en moins d'une minute » seulement si l'hébergement permet de la changer sans redémarrage.

---

## 6. Limites fonctionnelles à connaître (pas des questions, des faits)

À garder en tête pour ne pas promettre plus que ce qui existe.

- Pas de **relevé bancaire** groupé pour les sources autres que CODA : R06 sans relevé garde un calcul plat.
- Pas de **notion d'exercice court** adaptée dans les seuils de la clôture ; pas de cession partielle d'immobilisation ; pas d'annulation d'une cession.
- **Lettrage partiel manuel en devise refusé** ; devise par défaut d'un tiers enregistrée mais non préremplie.
- Pas de **budget** dans LedgerFlow (R11 bloqué tant que le contrat BudgetFlow n'est pas confirmé) ; `get_budget_vs_actual` retiré de l'agent.
- **Exports** PDF/JSON absents pour plusieurs rapports ; PDF via Prawn (Windows-1252 : les caractères hors Europe de l'Ouest s'impriment « ? »).
- **Notifications** : pas d'e-mail pour plusieurs abonnements, pas de relance automatique d'un envoi en échec, un seul destinataire par client.
- **Jeux de test fictifs** : fichiers CODA fabriqués, jeu de référence de 200 lignes construit dans le spec (le taux de 87,5 % ne dit rien sur de vrais dossiers), cas d'agent inventés.
- **Fenêtre d'horodatage** B03a : l'instant d'une validation est pris dans la transaction, pas au `COMMIT` (écart de quelques millisecondes, plus pour un gros lot).
- Les écrans **fr/nl** du portail B02a/B02b sont en anglais seulement.

---

## 7. Mes recommandations pour atteindre l'objectif « utilisable sans problème »

### 7.1 Choisir les bons interlocuteurs
1. **Un comptable ou expert-comptable belge** à l'aise avec la TVA des PME, les clôtures et Intervat, et idéalement avec la forme juridique visée. Il couvre §1 (et valide les comptes de §1.2). Si possible un seul interlocuteur sur tout §1, pour la cohérence.
2. **Un juriste** (droit numérique / RGPD) pour §2. Un **délégué à la protection des données** si l'agent ou le portail sont ouverts.
3. **Votre banque** (Crelan) pour §3 X1–X3.
Le point de départ est un échange court pour cadrer : forme juridique, volumes, outils actuels, exigences éventuelles sur le logiciel comptable utilisé (*je ne sais pas s'il existe en Belgique une exigence de conformité ou de certification pour un logiciel de comptabilité : question à poser*), conservation, piste d'audit.

### 7.2 Procéder par lots, avec livrables écrits
- **Lot A (le plus important)** : T1–T7, C1–C4, A1–A2. Livrable : un courriel ou une lettre par lot, daté et signé, listant ce qui est validé, corrigé ou refusé.
- **Lot B** : C5–C9, D1–D3, I1–I2, L1–L5, K1–K3, R1–R4.
- **Lot C** : tout le reste, seulement pour les fonctions que vous activerez.
Chaque validation obtenue est consignée au §9, puis reportée dans le fichier source (la règle de la fonction F12 va déjà dans ce sens : validation consignée avant application).

### 7.3 Faire une « marche parallèle »
Avant de vous fier au logiciel, **tenir en double une petite société réelle pendant un trimestre de TVA et une clôture** : la comptabilité officielle reste celle du comptable ; LedgerFlow reçoit les mêmes pièces. On compare balance, TVA (grille par grille), bilan et résultat. Chaque écart est soit un bug, soit une règle à corriger. C'est la seule preuve qui vaut « validé par un cycle complet » (O2).

### 7.4 Réduire le périmètre au démarrage
- Garder éteints les drapeaux dont la validation n'est pas faite : `f12` (consolidation), agent IA, portail client (palier 3), Peppol en production tant que X4/X5 ne sont pas levés, `f11` si aucune opération en devise.
- Démarrer par des cas simples : opérations nationales, TVA 21/12/6 %, un seul exercice de 12 mois.
- Garder la **validation humaine** : brouillons par défaut, quatre yeux activé, lettrage automatique éteint, relances sans envoi automatique.
- Ne pas parler de produit « certifié », « conforme » ni « prêt » tant que le §1 lot A n'est pas validé.

### 7.5 Dossier à remettre au comptable
Le tableau `VAT_grid_target.md` et les 10 à 15 cas chiffrés ; le plan `pcmn_commercial.json` (et `pcmn_asbl.json` si besoin) ; `company_abridged.yml` ; un jeu de référence exporté (`db/seeds/reference_ledger.rb`) avec balance, grand livre, déclaration TVA, bilan, résultat ; une facture PDF par régime ; les textes de relance ; un dossier de clôture d'exemple ; un fichier XML de déclaration.

### 7.6 Garde-fous (faits le 2026-10-20, sauf les deux derniers)
- **Bandeau « non validé par un comptable »** : affiché sur la liste et le détail des déclarations TVA, et sur les comptes annuels, tant qu'aucune validation n'est en vigueur pour la règle (V13).
- **Validation consignée par règle** : table `accounting_rule_validations` (qui, en quelle qualité, quand, où c'est écrit ; une seule validation en vigueur par société et par règle, révocable). Règles gérées : `vat_declaration`, `annual_accounts`. Écran administrateur : Réglages > Accountant validations (enregistrer, révoquer, audité). Équivalent en ligne de commande : `bin/rails "rules:validate[ENTITY_ID,vat_declaration,NOM,QUALITE,REFERENCE]"` ; retirer : `bin/rails "rules:revoke[ENTITY_ID,vat_declaration]"`. Ajouter une règle = l'ajouter à `Accounting::RuleValidation::RULES` et poser le partial `accounting/shared/_rule_validation_notice` sur ses écrans.
- **Test de contrat TVA** : `spec/contract/vat_declaration_cases_spec.rb`, alimenté par `spec/fixtures/vat_cases.yml` (6 cas : ventes 21/12/6 %, achats sur comptes 60x, 61 et 24). Les valeurs attendues viennent de `VAT_grid_target.md`, pas de la sortie du code ; le fichier est marqué `draft` jusqu'à relecture. **À compléter avec le comptable** : intracom, autoliquidation, export, avoirs, prorata, franchise (T1).
- **Pas fait : migration 491/493** (C1). Elle dépend de la réponse du comptable ; l'écrire avant risquerait de déplacer des données sur une hypothèse.
- **Pas fait : réinitialisation du TOTP par un propriétaire et codes de secours** (V1). Ce n'est pas un garde-fou léger : il touche l'authentification et demande des décisions (durée de validité des codes, qui peut réinitialiser, second facteur exigé pour le faire). À traiter comme une capacité à part.

---

## 8. Table de réduction : ce qui peut rester éteint

| Si vous n'utilisez pas… | Vous pouvez ignorer |
|---|---|
| Consolidation (`f12`) | G1 |
| Agent IA | IA1–IA4, J4, V10 |
| Portail client (palier 3) | J1, J2, S1–S3, X7 |
| Multi-devises (`f11`) | D1–D3, X (taux) |
| Immobilisations | I1, I2, T5 (partie révision 5/15 ans) |
| Relances clients (`f09`) | R1–R4 |
| Peppol en production | T9, X4, X5 |
| Paiements fournisseurs SEPA | L4, X1, X3 |

Ce qui ne peut **pas** rester éteint : T1–T4, T7, C1–C4, C7, K1, A1 (si vous produisez des comptes annuels), O1–O2, S5.

---

## 9. Validations obtenues (à remplir)

| Date | Point | Professionnel et qualité | Résultat (validé / corrigé / refusé) | Où c'est écrit |
|---|---|---|---|---|
| | | | | |

---

## 10. Index des sources

`docs/dev/reports/QUESTIONS.md` (rapports, TVA, PCMN, devises) · `docs/dev/features/QUESTIONS.md` (F01–F13) · `docs/dev/agent/QUESTIONS.md` et `DATA_PROCESSING.md` (agent IA) · `docs/dev/signature/QUESTIONS.md` (B01–B03) · `docs/dev/HANDOFF_next_steps.md` (écarts TVA, avoirs, amortissements, comptes annuels, relances, reprise) · `docs/dev/VAT_grid_target.md` · `docs/dev/DEPLOYMENT_PLAN.md` §6 et §9 (décisions et hors-code avant le palier 3) · `docs/dev/audit-foreign-bank-accounts.md` · `docs/dev/reports/R09.md`.

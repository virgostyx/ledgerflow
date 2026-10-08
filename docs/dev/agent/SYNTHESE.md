# Agent IA de LedgerFlow — synthèse pour la mise en service

*État au 9 octobre 2026. Ce document résume ce qui est livré, ce qui ne l'est pas, ce qui a été mesuré et ce qui ne l'a pas été, et ce qu'il faut décider ou faire valider avant d'ouvrir l'agent à de vrais utilisateurs. Le détail se trouve dans `A01.md` à `A12.md`, `QUESTIONS.md` et `DATA_PROCESSING.md`.*

## 1. En une page

- Les **douze capacités** de la spec (`spec.md`, A01 à A12) sont codées, testées et commitées, derrière le drapeau `agent` de l'entité et le réglage du propriétaire. Rien n'est actif par défaut.
- La suite de tests complète passe : **7 697 exemples, 0 échec, couverture 97,9 %** (seuil 95 %). Rubocop et brakeman sont propres. **217 cas d'évaluation** passent en mode simulé.
- **Le vrai modèle n'a jamais été interrogé.** Toutes les mesures « 100 % » sont celles du harnais d'évaluation avec un modèle simulé (script ou oracle) : elles prouvent que les garde-fous, les contrôles et les métriques fonctionnent, pas que le modèle répond bien. Aucun chiffre de qualité de réponse n'existe encore.
- **Rien n'est prêt pour de vraies données** tant que quatre choses ne sont pas faites : le mode réel mesuré, la relecture du contenu comptable par un comptable, la validation juridique de `DATA_PROCESSING.md`, et les décisions de la section 5.

## 2. Ce que fait l'agent, capacité par capacité

| # | Capacité | Ce qu'elle permet | Écrit-elle dans les livres ? |
|---|---|---|---|
| A01 | Socle conversationnel | Panneau (Turbo/Stimulus), conversations privées à leur auteur, arrêt, avis, API REST (`agent:use`), consultation exceptionnelle par un propriétaire (motif, second facteur, avis à l'auteur) | Non |
| A02 | Outils de lecture | 27 outils en lecture seule (rapports, grand livre, balance âgée, TVA, anomalies, audit…), enveloppe standard, montants en chaînes décimales | Non (garde dynamique : transaction en lecture seule) |
| A03 | Sécurité | Droits relus à chaque appel, contenu des données traité comme non fiable, détecteur d'injection (alerte, pas défense), validation de la réponse, événements de sécurité, corpus d'attaques | Non |
| A04 | Confidentialité | Consentement versionné, masquage des identifiants et des noms avant envoi, mode restreint, ce qui a été envoyé consultable, rétention, export et effacement d'une personne | Non |
| A05 | Réponses chiffrées vérifiables | Outil `calculate` (décimaux exacts), ancrage des montants (nouvelle tentative puis marque), citations vérifiées, bouton « Vérifier », « Expliquer » | Non |
| A06 | Base de connaissance | Documents datés et relus, recherche plein texte, aucune référence légale inventée, rapport de lacunes | Non |
| A07 | Propositions d'écriture | `propose_entry` / `propose_task` validés par le serveur, carte, création d'un **brouillon** au clic de l'auteur, revalidation au clic | **Seulement un brouillon, au clic d'une personne** |
| A08 | Explication d'anomalies | 22 protocoles de diagnostic, `get_finding_context`, `get_variation`, priorisation | Non |
| A09 | Lecture de documents | Mode `text_only` (texte masqué, aucun fichier), appel isolé à un seul outil, ancrage des champs, validations déterministes, confirmation par la personne | Non (les champs confirmés passent par la porte de F03) |
| A10 | Résumé et mémoire | Résumé quotidien/hebdomadaire sans modèle, alertes, notes de dossier proposées puis confirmées | Non |
| A11 | Rédaction assistée | Brouillons de relances, demandes, commentaires, réponses ; profil de style ; jamais envoyés | Non |
| A12 | Évaluation | Cas en YAML, exécution simulée ou réelle, métriques, seuils, rapport, étape de CI | Non |

## 3. Garde-fous qui tiennent (et comment on le sait)

| Garde-fou | Comment il est vérifié |
|---|---|
| **L'agent n'écrit jamais dans la comptabilité**. Le seul chemin vers un brouillon est le clic d'une personne | `proposals_boundary_spec` lit le code ; chaque cas d'évaluation vérifie que les livres sont inchangés ; les outils tournent dans une transaction en lecture seule |
| **Aucun envoi** (relance, e-mail, SEPA) : l'agent n'a pas d'outil d'envoi | Aucun outil n'appelle un service d'envoi (spec du catalogue) ; un texte de l'agent est exclu de l'envoi automatique |
| **Chaque chiffre vient d'un outil** | Ancrage des montants dans la réponse, les calculs et les brouillons ; un montant, une date ou un numéro de facture inventé est marqué ou remplacé par un emplacement |
| **Les droits de la personne, pas plus** | Droits relus à chaque appel ; résumés et outils filtrés par rôle ; aucun `company_id`/`user_id` accepté en argument |
| **Isolation entre sociétés** | Tests à deux entités à chaque couche (outils, base de connaissance, notes, brouillons) |
| **Les données sont des données** | Textes de tiers, documents, notes : balisés, nettoyés, détecteur d'injection, aucun effet sur les outils |
| **Confidentialité** | Masquage des identifiants et noms avant envoi, mode restreint, consentement versionné, « ce qui a été envoyé » consultable, rétention, export et effacement d'une personne (conversations, notes, résumés, propositions, lectures de documents) |
| **Interrupteur d'urgence** | `AGENT_KILL_SWITCH` relu à chaque question |
| **Appel au fournisseur impossible hors production** | `AGENT_ALLOW_LIVE_PROVIDER` obligatoire ; le jeu d'évaluation réel n'utilise que des données inventées |

## 4. Ce qui n'est PAS fait, ni mesuré

**Pas mesuré (le plus important)**
- Aucun appel au vrai modèle. Qualité, taux d'outil bien choisi, exactitude des chiffres cités, calibration de la confiance de la lecture de documents, respect du profil de style, rappel de la recherche sur la vraie base : **à mesurer** avec `bin/rails agent:evals` et `agent:evals:documents` en `MODE=real`.
- Temps de réponse (95e centile), coût réel par question, concurrence de Puma avec les réponses en flux.
- Le schéma strict des outils imbriqués (propositions d'écriture) n'a pas été essayé chez le fournisseur : il peut limiter le nombre de paramètres facultatifs.
- Les cas d'évaluation ont été **écrits par moi** et par un harnais ; ni un comptable ni un tiers ne les a relus.

**Fonctions non livrées** (toutes documentées dans la fiche de la capacité)
- `full_document` (envoyer le fichier tel quel) : non offert, décision à prendre (section 5).
- Lecture d'un scan sans texte local ; recherche vectorielle de la base de connaissance (aucun fournisseur d'embeddings choisi) ; traduction de la requête par un modèle léger.
- Propositions `reconcile`, `reversal`, `note` ; déclencheurs « Proposer une écriture » depuis un document, un message Peppol, une ligne de relevé ; lien entre l'écriture créée et son document.
- « Expliquer » sur R06, R08 et le bandeau R04 ; boutons de rédaction sur une tâche (F08) et à l'étape 14 de la clôture (F10).
- Résumé rédigé par l'agent (optionnel dans la spec) ; section « budget » (R11 n'existe pas) ; seuils réglables par personne ; réglage « en congé ».
- Retour arrière du manifeste (changer de consigne sans redéployer) ; modèle-juge et revue humaine des cas ; exécution nocturne du mode réel ; budget en euros.
- Pas de `mutant` (spec §17) ni de `i18n-tasks` : non installés.

**Constats sur l'existant, non corrigés** (hors périmètre de l'agent)
- Le contrôle C13 ne signale pas un compte de produits hors rubrique alors que le bilan se déséquilibre (invariant I6) ; la spec parle de 17 contrôles et 11 invariants, le code a 15 contrôles et rejoue 4 invariants.
- Les agrégations de la balance âgée, du grand livre et des lignes non lettrées se font en Ruby (règle du projet : SQL) — risque de lenteur sur un gros dossier ; `get_ledger` refuse au-delà de 5 000 lignes.

## 5. Décisions à prendre, dans l'ordre

1. **Le mode réel.** Fournir une clé, un budget plafonné (`BUDGET_TOKENS`) et un environnement dédié ; lancer le jeu complet (3 passages par cas). Sans cela, aucune autre décision de qualité n'a de base. *Recommandation : à faire en premier.*
2. **La validation juridique** de `DATA_PROCESSING.md` (sous-traitance, transferts hors UE, durée chez le fournisseur, base légale, droits) par le DPO ou un conseil, avant la première acceptation réelle du consentement. Contient des questions ouvertes.
3. **Le mode `full_document`** (A09) : oui ou non. L'envoi du document non masqué est une décision de risque, pas de technique ; *recommandation : non tant que 2 n'est pas faite*.
4. **Qui relit le contenu comptable** : les 22 protocoles de diagnostic (A08, tous « non validés »), les écritures de référence des cas de propositions (A07), le contenu de la base de connaissance (A06, aucun document réel n'est livré ; qui charge et relit le PCMN ?), le seuil de revue renforcée (5 000 EUR par défaut).
5. **Les réglages par défaut de confidentialité** : e-mail du résumé avec ou sans détails, retention (30/90/365 jours), classes de données masquées, mode restreint.
6. **Quatre-yeux de la base de connaissance** : exiger la relecture par une autre personne que l'auteur pour toute société qui s'en sert.
7. **Le coût** : activer le cache des consignes (D3, désactivé), fixer les quotas par société (20/heure et 100/jour par personne aujourd'hui), choisir la périodicité du mode réel.
8. **Le déploiement** : les files `agent_interactive` (réponses) et `agent_batch` (rétention, résumé, lots) n'ont pas de `config/queue.yml` : Solid Queue les traite par défaut (toutes les files), ce qui mélange les réponses interactives et les lots ; créer ce fichier si l'on veut des travailleurs séparés. La tâche horaire du résumé et la rétention quotidienne sont dans `config/recurring.yml` (production seulement). Clé du fournisseur dans les credentials, chiffrement Active Record configuré en production.

## 6. Plan de mise en service proposé

1. **Environnement de pré-production** avec les migrations (14 migrations `agent_*` et `knowledge_*`), la clé du fournisseur, `AGENT_ALLOW_LIVE_PROVIDER`, le jeu de démonstration (`agent:evals` crée deux entités inventées : ne pas le lancer sur une base de production).
2. **Mesure** : `MODE=real RUNS=3 BUDGET_TOKENS=… bin/rails agent:evals` puis `agent:evals:documents`. Lire le rapport : portes à zéro (montant non ancré, injection, écriture sans clic, fuite entre sociétés, proposition déséquilibrée), planchers (choix d'outil ≥ 90 %, chiffres exacts ≥ 95 %, propositions conformes ≥ 90 %), cas instables.
3. **Corriger** consigne et descriptions d'outils d'après les échecs ; chaque changement change l'empreinte du manifeste (stockée sur chaque réponse) et doit repasser par l'évaluation.
4. **Relecture comptable** des protocoles, des écritures de référence et de la base de connaissance ; passer à `validated: true` ce qui l'est.
5. **Pilote** sur une société consentante : drapeau `agent` activé pour elle, propriétaire qui accepte le consentement, 2 à 5 personnes, lecture seule d'abord (A01 à A05), puis propositions (A07), puis documents (A09) et rédaction (A11). Surveiller la page des événements de sécurité et le rapport de lacunes.
6. **Élargir** par société, avec le même parcours ; garder l'interrupteur d'urgence documenté pour l'exploitation.

## 7. Risques à garder en tête

| Risque | Ce qui le limite | Ce qui reste |
|---|---|---|
| Réponse chiffrée fausse présentée avec assurance | Ancrage + marque `[unverified figure]` + bouton « Vérifier » | Un chiffre à deux décimales seulement est contrôlé ; un calcul écrit autrement ; non mesuré en réel |
| Injection par une donnée (nom de tiers, document, note, e-mail collé) | Données non fiables, outils en lecture seule, un seul outil dans l'appel de lecture de document, rien ne s'exécute | Le détecteur n'est pas une défense ; un modèle qui obéirait dans une réponse ne peut ni écrire ni envoyer, mais pourrait induire une personne en erreur |
| Fuite de données vers le fournisseur | Masquage, mode restreint, consentement, journal de ce qui est envoyé | Le texte libre part tel quel par défaut (réglable) ; les termes juridiques ne sont pas validés |
| Coût qui dérive | Quotas, limites de tours et de tokens, estimation avant lot | Pas de budget en euros ; le catalogue d'outils (32,7 Ko) est envoyé à chaque question |
| Mauvaise écriture créée par confiance excessive | Validation déterministe, brouillon seulement, revue renforcée au-delà d'un seuil, quatre-yeux de l'entité | Les écritures de référence ne sont pas relues ; l'habitude de cliquer sans lire |
| Protocole de diagnostic erroné | Chaque réponse dit « aucun protocole validé » et présente les causes comme hypothèses | Tant que personne ne les a relus |

## 8. Où trouver quoi

| Besoin | Fichier |
|---|---|
| La spec d'origine | `docs/dev/agent/spec.md` |
| L'audit initial (écarts spec / code) | `00-audit.md` |
| Une capacité en détail : ce qui existe, critères d'acceptation, écarts | `A01.md` … `A12.md` |
| Les décisions à valider, une section par capacité | `QUESTIONS.md` |
| Le traitement des données et les questions juridiques | `DATA_PROCESSING.md` |
| Lancer l'évaluation | `bin/rails agent:evals[A05]` · `MODE=real RUNS=3 BUDGET_TOKENS=200000 bin/rails agent:evals` · `bin/rails agent:evals:documents[100]` |
| Cas d'évaluation | `app/services/agent/evals/cases/*.yml` (217 cas : A02 14, A03 6, A04 5, A05 67, A06 38, A07 24, A08 28, A09 7, A10 12, A11 16) |
| Consignes de l'agent | `app/services/agent/prompts/system.md` |
| Réglages (modèles, limites, quotas) | `config/agent.yml` |

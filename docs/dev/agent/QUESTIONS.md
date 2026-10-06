# Questions ouvertes et décisions — Agent IA

Décisions prises pendant l'audit (`00-audit.md`), validées par l'utilisateur le 2026-10-06 en suivant les recommandations. Les points juridiques et comptables restent à faire valider par un professionnel.

## Décisions validées (D1 à D11)
- **D1 — Fournisseur et modèles.** Un seul point d'appel, `Agent::ModelGateway`, derrière une interface. Client HTTP via Faraday (déjà présent) sauf si la documentation officielle de l'API montre qu'un SDK Ruby officiel gère proprement le flux et les outils: à vérifier au démarrage d'A01, avant d'écrire le client. Identifiants de modèles et prix dans la configuration ou les credentials, jamais dans le code.
- **D2 — Langues.** L'agent répond dans la langue de l'utilisateur (fr ou en). Le panneau et ses libellés sont en anglais (règle du projet). Le néerlandais est reporté.
- **D3 — Cache de prompts.** Désactivé en P0. Activation après lecture de la documentation officielle et mesure; seulement pour la partie statique (consigne, définitions d'outils).
- **D4 — Embeddings (A06).** Recherche plein texte PostgreSQL d'abord. pgvector et le fournisseur d'embeddings: décision reportée à P1, avec les conséquences sur la confidentialité.
- **D5 — Mode de document (A09).** `text_only` par défaut. `full_document` seulement avec l'accord explicite de l'utilisateur.
- **D6 — Rétention.** 90 jours par défaut pour les conversations (30, 90 ou 365 au choix du propriétaire). Les métadonnées d'audit suivent la durée d'audit de la société.
- **D7 — Quotas.** 20 questions par heure et 100 par jour par utilisateur, 3 générations simultanées par société. Le budget mensuel est fixé après un pilote, pas avant.
- **D8 — Flux.** Turbo Streams et Solid Cable (existants), pas de SSE. La charge côté Puma est à mesurer.
- **D9 — Interrupteur d'urgence.** Réglage de plateforme lu à chaque requête de l'agent (variable d'environnement `AGENT_KILL_SWITCH`, relue sans redémarrage de l'application quand l'hébergement le permet). Pas de table pour l'instant.
- **D10 — Limites de débit.** Pas de `MemoryStore` par processus pour l'agent: les quotas se calculent sur `agent_usage` en base.
- **D11 — `get_budget_vs_actual`.** Retiré du P0: LedgerFlow n'a pas de budget et BudgetFlow n'est qu'entrant. Il revient avec R11.

## Correspondance des permissions (C0.3)
- Les noms de la spec (`accounts.view`, `partners.view`, `entries.view`) n'existent pas dans `Permissions::MATRIX`. Les outils de lecture utilisent les permissions existantes: `records.view` et `records.list` (comptes, tiers, écritures), `reports.view`, `documents.view`, `audit.view`.
- Six permissions ajoutées: `agent.use`, `agent.propose`, `agent.memory.manage`, `knowledge.manage`, `agent.configure`, `agent.conversations.review`.
- **Auditeur externe et `agent.use`**: la spec dit « configurable ». Par défaut, refusé (comportement le plus prudent). Un propriétaire peut l'accorder par un rôle personnalisé.
- **Lecteur** (`manager`): `agent.use` accordé, `agent.propose` refusé, comme la spec.
- `agent.configure` et `agent.conversations.review` sont réservés au propriétaire. Ils restent assignables à un rôle personnalisé, comme les autres permissions de propriétaire déjà dans la matrice. À valider: faut-il les réserver comme `users.manage`?
- Aucune restriction par compte n'existe dans F01 (seulement par journal), contrairement à ce que dit le §6 de la spec. Les outils appliquent la restriction par journal.

## Écarts de la spec avec le code (à corriger dans la spec ou à assumer)
- Contrôles R19: 15 contrôles réels (C01 à C07, C09, C11 à C14, C16 à C18), pas 17. Les protocoles d'A08 suivent le code.
- `Ledger::PostEntry` s'appelle `Accounting::PostJournalEntry`. Il n'existe pas de service de création de brouillon.
- L'API de l'agent utilisera les clés `lf_…` (ApiClient et `action_scopes`), pas de JWT.

## Points qui attendent encore une réponse
- Migration `partners.is_natural_person` (nullable, inconnu = personne physique) et `journal_entries.created_via`: validées sur le principe, à écrire en A04 et A07.
- Extraction d'un service `Accounting::CreateDraftEntry` du contrôleur: avant A07.
- Gems à ajouter: un rendu Markdown assaini (A01), mutant et i18n-tasks (avant la première « définition de terminé »).

## A01 — écarts avec la spec, à valider
- **Emplacement du code** : `app/services/agent/` et `app/models/agent/`, pas `app/agent/` (voir A01.md).
- **Aucun lien dans les réponses** avant A05 : les liens vers la comptabilité seront construits par l'application à partir de références vérifiées. Plus strict que la spec (qui tolérait un lien externe signalé).
- **Gem `commonmarker`** ajouté (Markdown à tables, HTML brut écarté par l'analyseur) puis assaini par `rails-html-sanitizer`.
- **API** : « flux » remplacé par un `202` et une lecture de la conversation (D8), non faite à ce jour.
- **Mémoire des rapports et quotas** : les quotas se comptent sur les questions enregistrées. Une question supprimée avec sa conversation ne compte plus : un utilisateur pourrait contourner la limite en supprimant. À durcir avec `agent_usage` (A04/§16).
- **Interrupteur d'urgence** : variable d'environnement relue à chaque requête, donc effective « en moins d'une minute » seulement si l'hébergement permet de la changer sans redémarrer. Sinon, ajouter un réglage de plateforme en base.

## A02 — décisions à valider
- **`get_vat_return`** : lit `VatGridQuery` (écritures validées, statut `posted` seulement, comme l'écran). Les écritures extournées n'y figurent pas : à confirmer avec R09.
- **Soldes présentés** : `get_trial_balance` donne l'ouverture et la clôture en débit/crédit nets (comme l'écran), `get_ledger` donne le solde courant dans le sens normal du compte, avec ce sens dit dans `filters_applied`. Un modèle qui lirait un solde sans le sens risquerait de se tromper ; le sens est dans chaque réponse.
- **Audit de l'agent** : chaque appel d'outil est une ligne de la piste d'audit, ce qui l'allonge vite (15 outils, plusieurs appels par question). À surveiller ; une agrégation par message est possible si la piste devient trop bavarde.
- **`get_audit_trail`** donne l'adresse e-mail de l'auteur (classe `personal`), pas le détail des changements.
- **Lecture seule en base** : le savepoint annulé après chaque outil suppose qu'aucun outil n'a d'effet de bord utile en base (c'est le cas : `Rails.cache` est sur une autre base en production).

## A03 — décisions à valider
- **Noms de tiers traités comme du texte non fiable** : balayés et coupés à 500 caractères comme les libellés. Quand A04 masquera les noms de personnes physiques par des jetons, ce risque diminue pour elles, pas pour les sociétés.
- **Seuil d'alerte** : 5 signes d'attaque en 24 heures (`Agent::SecurityEvent::ALERT_THRESHOLD`), à régler après un pilote.
- **Faux positifs du détecteur** : un libellé réel qui contiendrait une adresse web (« voir https://… ») est signalé (badge et événement), sans autre effet. Acceptable ? Sinon, retirer le motif `url` du signalement.
- **`question` et `comment` filtrés des journaux** pour toute l'application (le filtre porte sur le nom du paramètre) : cela masque aussi les commentaires de tâches dans les journaux de requêtes.
- **Restrictions par journal** : voir A03.md ; si la spec veut qu'elles bornent aussi les rapports, il faut d'abord que les écrans le fassent.

## A04 — questions juridiques (à faire valider par le délégué à la protection des données ou le conseil du propriétaire)
Voir la liste complète dans `DATA_PROCESSING.md` : conservation chez le fournisseur, usage pour l'entraînement, région de traitement, transferts hors Union européenne, sous-traitants, secret professionnel du cabinet, base légale, AIPD, relecture du texte de consentement.

## A04 — décisions techniques à valider
- **« Voir ce qui a été envoyé » garde la charge utile** (masquée, chiffrée) sur chaque réponse, alors que la spec dit de ne pas la conserver pour ne pas dupliquer des données sensibles. Sans elle, la reproduction « exacte » est impossible (les résultats d'outils ne sont pas conservés). Elle ne contient que du masqué, est chiffrée et part avec la conversation ; à valider.
- **Les questions tapées sont conservées telles quelles** (chiffrées), avec les vrais noms et numéros de la personne : c'est ce qui permet de retrouver une personne dans les conversations, et à l'auteur de se relire. Elles partent masquées.
- **Mode `mask` pour les montants, dates et références** : sans sens de masquage utile, il se comporte comme `block`.
- **Montants et dates** sont reconnus par leur forme (chaîne à deux décimales, date ISO), pas par une classe déclarée champ par champ : le contrat de sortie des outils (A02) l'assure.
- **Un tiers dont la nature est inconnue est masqué** : tous les tiers existants le sont tant que le champ n'est pas rempli. Les réponses restent lisibles pour la personne (les noms reviennent), mais le modèle raisonne sur des jetons ; remplir `is_natural_person` des sociétés améliore ses réponses.
- **Chiffrement déterministe** de la table des pseudonymes : même valeur, même chiffré, pour retrouver une personne ; c'est un compromis assumé (un attaquant avec la base mais sans la clé ne lit rien, mais voit quelles conversations partagent un nom).
- **Notes de dossier et propositions** (A10, A07) : le droit d'accès et d'effacement ne les couvre pas encore, elles n'existent pas.
- **Document mode** (A09) : non réglable pour le moment (aucune capacité n'envoie de document).

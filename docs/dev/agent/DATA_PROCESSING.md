# Agent IA — flux de données vers le fournisseur du modèle

Ce document décrit ce qui part de LedgerFlow vers le fournisseur du modèle de langage, sous quelle forme et pour combien de temps. Il **ne tranche pas** les points juridiques : ils sont listés à la fin et dans `QUESTIONS.md`, à faire valider par le délégué à la protection des données ou le conseil du propriétaire.

## Le fournisseur
Anthropic, par l'API des modèles Claude. Identifiants de modèles dans `config/agent.yml` ; clé d'API dans les credentials Rails (`anthropic.api_key`) ou `ANTHROPIC_API_KEY`, jamais dans le dépôt. Un seul point d'appel : `Agent::ModelGateway`. Hors production, il refuse d'appeler le vrai fournisseur sans `AGENT_ALLOW_LIVE_PROVIDER` : aucune donnée réelle ne part d'un poste de développement.

## Ce qui part, et seulement sur une question
Rien ne part tant qu'une personne ne pose pas une question. Chaque appel au modèle envoie :
1. **La consigne du système** : les principes de l'agent (fichier du dépôt), le nom de l'entité, la date, la langue, l'écran et la référence de l'objet ouvert.
2. **La conversation** : les tours précédents (la question de la personne et les réponses du modèle).
3. **Les résultats des outils** que le modèle a consultés (rapports, recherche de tiers, d'écritures, de documents). **Jamais le contenu d'un document** : aucun outil ne le renvoie.

Rien d'autre : ni l'écran, ni d'autres conversations, ni un accès direct à la base. Le modèle n'a aucun outil d'écriture, d'envoi ni d'accès au réseau.

## Ce qui est masqué avant l'envoi (`Agent::Redactor`)
Juste avant l'appel, sur tout ce qui part. Réglable par le propriétaire, classe par classe : envoyé tel quel (`send`), masqué (`mask`), jamais envoyé (`block`). Mode restreint : seuls des agrégats partent.

| Classe | Défaut | Ce que devient la valeur |
|---|---|---|
| Références techniques et codes | envoyé | tel quel |
| Montants, soldes, dates | envoyé | tel quel (en `block` : `[blocked]`) |
| Noms de personnes physiques | masqué | `PERSONNE_017`, le même jeton dans toute la conversation |
| Numéros de compte bancaire | masqué | les quatre derniers caractères (`IBAN …7034`) |
| Numéros de TVA et d'entreprise | masqué | `TVA_003` |
| Texte libre | envoyé après nettoyage | caractères cachés retirés, 500 caractères, balayé à la recherche d'IBAN, de numéros nationaux, de TVA et de noms |

- Un tiers dont la nature n'est pas connue (`partners.is_natural_person` vide) est traité comme une personne physique. Seul un tiers marqué « société » garde son nom.
- Un **numéro de carte bancaire** ou un **mot de passe** ne part jamais, quels que soient les réglages.
- Les IBAN, numéros nationaux belges et numéros d'entreprise sont reconnus **avec leurs chiffres de contrôle** : un nombre qui y ressemble seulement n'est pas touché.
- Ce que la personne tape est examiné avant l'envoi : un IBAN ou un numéro national déclenche un avertissement avec le choix.
- La table des jetons est propre à la conversation, chiffrée, jamais envoyée : la personne relit les vrais noms dans la réponse.
- Sous chaque réponse, « Voir ce qui a été envoyé » montre la charge utile telle qu'elle est partie, après masquage.

## Ce qui est gardé dans LedgerFlow
- Les conversations (messages, arguments d'outils, avis, charge utile envoyée après masquage) sont **chiffrées**, visibles de leur auteur seul, et supprimées après la durée choisie (30, 90 ou 365 jours ; 90 par défaut) par `Agent::RetentionJob`, chaque nuit. La personne peut les exporter et les supprimer.
- La **piste d'audit** garde qu'un outil a été consulté, par qui et quand, jamais ce qui a été dit.
- Les **événements de sécurité** gardent leur nature et l'outil ; l'extrait (masqué, chiffré) part avec la conversation.
- Le **consentement** du propriétaire est enregistré par version du texte (qui, quand). Sans consentement à la version courante, l'agent est indisponible pour l'entité.
- Un propriétaire peut chercher une personne physique dans les conversations de l'entité pour exporter ce qui la concerne ou l'effacer ; chaque demande est écrite dans la piste d'audit avec son motif et une empreinte du nom (pas le nom).

## Questions à faire valider (reprises dans `QUESTIONS.md`)
1. **Conservation chez le fournisseur** : durée, et options de conservation réduite selon le contrat.
2. **Usage pour l'entraînement** : exclu par le contrat, ou à demander ?
3. **Région de traitement** et **transferts hors Union européenne**.
4. **Sous-traitants** du fournisseur.
5. **Secret professionnel** : un cabinet comptable peut-il envoyer ces données à un fournisseur d'IA, et à quelles conditions ?
6. **Base légale** et **information des personnes** dont le nom figure dans les livres (même masqué, le nom reste dans LedgerFlow ; masqué, il ne part pas).
7. **Analyse d'impact** (AIPD) : nécessaire ou non pour cet usage.
8. **Texte de consentement** (`app/views/agent/settings/_consent.html.erb`) : à relire par le conseil du propriétaire avant la première acceptation réelle.

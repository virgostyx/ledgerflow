# Démarrage fonctionnel en production (palier 1)

À faire une fois, après `bin/kamal setup` et ses contrôles (`DEPLOYMENT_PLAN.md` §4, étapes 1 à 5). Le palier 1 est le cabinet seul : portail fermé (`PORTAL_HOST` absent), drapeaux `b02a`, `b02b`, `b02c` à faux.

## À ne jamais faire en production

- `db:seed` et `db:seed:replant` : ils créent les comptes de démonstration (`admin@ledgerflow.test`, mot de passe `password123!`), et `replant` **efface** tout.
- `OPEN_SIGNUP=1` : la création de compte libre est **fermée par défaut** en production (`/users/sign_up` renvoie à la connexion). Les collègues entrent par invitation (étape 5).
- Poser `PORTAL_HOST`, les variables Peppol, agent, BudgetFlow ou webhooks avant d'avoir décidé de le faire.

## Ce que l'application charge toute seule

À chaque démarrage du conteneur (`bin/docker-entrypoint`) : `db:prepare` (les 4 bases) puis `reference:load` : les **codes et grilles TVA** et les **devises**. Idempotent, rien n'est dupliqué. Sans ces données, la grille TVA lève `NotSeeded`.

## Étapes

1. **Premier administrateur** (le mot de passe se tape dans le terminal, 12 caractères au moins, jamais en argument) :
   ```
   bin/kamal app exec --interactive "bin/rails 'users:create_owner[vous@votre-domaine,Nom Complet]'"
   ```
   Il refuse de toucher un compte existant.
2. **Connexion** sur `https://app.ledgerflowmanagment.com`, puis création de la **société** (écran « Entities », nouvelle société). La création installe le plan comptable, les journaux par défaut, les axes analytiques et un exercice ouvert, et vous donne le rôle d'administrateur sur cette société. Vérifier ensuite le plan comptable et les journaux dans Réglages.
3. **Second facteur (F01)** : Réglages → Société → fonctions : cocher `f01`. L'obligation du second facteur ne s'applique **que** dans une société où `f01` est actif, aux membres qui peuvent valider, déverrouiller ou administrer. À la connexion suivante, enrôler l'application TOTP (ou une clé d'accès) et **ranger les codes de secours hors du serveur**.
4. **Intégrité (B03c)** : cocher `b03c`, puis créer la clé de signature (le dossier hôte doit exister, voir `server_preparation.md` §6) :
   ```
   bin/kamal app exec "bin/rails integrity:keys:generate"
   ```
   Noter l'empreinte affichée, vérifier `https://app.ledgerflowmanagment.com/.well-known/ledgerflow/keys.json`, sauvegarder le fichier de clé **chiffré et séparé** de la base. Sans clé, aucun certificat n'est scellé (le reste fonctionne).
5. **Inviter un collègue** (Réglages → membres) : le compte est créé avec un mot de passe inconnu et le courriel « choisissez votre mot de passe » part par le SMTP. **C'est le test du courriel sortant** (étape 8 du plan) : vérifier la réception, le lien (hôte `app.ledgerflowmanagment.com`, https) et les en-têtes SPF/DKIM/DMARC « pass ». Retirer ensuite l'invité si c'était un test.
6. **Autres drapeaux** : société par société, seulement ceux dont vous avez besoin (`f02`, `f03`, etc.). Pas `b02a`, `b02b`, `b02c` au palier 1.
7. **Reprise de données** (écritures, extraits bancaires) : à décrire à part avant la première reprise.

## Contrôles

- `bin/kamal app exec "bin/rails runner 'puts Accounting::VatCode.count, Accounting::Currency.count'"` : non nuls (13 codes TVA au moins).
- `/users/sign_up` : redirige vers la connexion.
- Une écriture de test, validée, visible au grand livre ; puis liste de contrôle du palier 1 (`DEPLOYMENT_PLAN.md` §8).

# Plan de déploiement en production — LedgerFlow

Rédigé le 2026-10-17, état du dépôt : `origin/development` = `8491c88` (suite complète : 9470 exemples, 98,02 %).
Ce document sert de point de départ à une **nouvelle session** : il dit où l'on en est, ce que le dépôt contient déjà, ce qui manque, dans quel ordre agir, et ce qu'il faut décider.

> **Règle absolue (spec signature §13, CLAUDE.md)** : aucun vrai client n'utilise le portail avant le **test d'intrusion externe**. Le déploiement se fait donc en **trois paliers** (§1). Le palier 3 (ouverture du portail) ne se fait pas tant que le test n'est pas passé et ses constats traités.

> **Règles de travail pour la session de déploiement** : ne jamais committer `docs/cloudflare credentials`, `config/master.key`, ni de valeur de secret ; ne rien pousser sans demande ; ne jamais lancer deux `rspec` à la fois ; montrer toute commande qui touche le serveur (`kamal ...`, `ssh`, `docker`) avant de l'exécuter ; demander accord avant toute action sur le serveur partagé avec BudgetFlow (**ne jamais modifier BudgetFlow sans accord explicite**).

---

## Contexte précisé le 2026-10-17

- **Serveur dédié à LedgerFlow** (plus de partage avec BudgetFlow) : les précautions « serveur partagé » des §0, §3.1 et §10bis tombent ou s'allègent ; `deploy.yml` doit être adapté (§2.8).
- L'utilisateur possède **un domaine** et **une adresse e-mail** : à renseigner dans la nouvelle session (nom du domaine, hébergeur du DNS, adresse, et son usage : expéditeur `MAILER_FROM` ? boîte de réception ? fournisseur de courrier ?). Aucune valeur n'est écrite dans ce document.
- À fournir aussi : adresse IP du serveur, système (distribution/version), utilisateur et port SSH, hébergeur (le port 25 est-il ouvert ?).

---

## 0. Ce que le dépôt contient déjà (vérifié le 2026-10-17)

| Élément | Fichier | État |
|---|---|---|
| Kamal 2.11, un seul serveur `budgetflow-production` (partagé avec BudgetFlow à l'origine), SSH `deploy` port 2221 | `config/deploy.yml` | écrit en juillet, **jamais mis à jour** pour B01–B03 ; **à repointer vers le serveur dédié** (§2.8) |
| Hôte public | `proxy.host: ledgerflow.budgetflowmanagement.com`, Let's Encrypt (A record nécessaire avant le 1er déploiement) | à confirmer |
| Image Docker | `Dockerfile` (ruby slim, `libvips`, `postgresql-client`, jemalloc, Thruster) | **il manque des outils** (§2.1) ; `RUBY_VERSION` par défaut `3.3.0` alors que `.ruby-version` = `3.3.5` (Kamal ne passe pas l'argument : à fixer) |
| PostgreSQL 16 en accessoire `ledgerflow-db`, port local `127.0.0.1:5433`, répertoire `data` | `config/deploy.yml` | OK ; pas de base distincte pour le rôle du portail |
| 4 bases en production : primary, cache, queue, cable (même instance) | `config/database.yml` | `bin/docker-entrypoint` fait `db:prepare` au démarrage du serveur |
| Solid Queue dans Puma (`SOLID_QUEUE_IN_PUMA=true`), `WEB_CONCURRENCY=1`, `RAILS_MAX_THREADS=5` | `config/deploy.yml` | **pas de `config/queue.yml`** : configuration par défaut de Solid Queue (1 worker, toutes les files). À vérifier que la file `agent_batch` est bien traitée |
| Tâches récurrentes (≈ 35, dont `PortalAdminJob` à la minute) | `config/recurring.yml` | section `production:` complète |
| Volume `ledgerflow_storage:/rails/storage` (fichiers Active Storage `local`) | `config/deploy.yml` | OK ; **pas de volume pour les clés de signature** |
| Sauvegarde | `bin/backup`, `docs/dev/backup_restore.md` | script prêt ; **cron non posé, copie hors serveur non faite, restauration jamais éprouvée sur le serveur** |
| Secrets Kamal | `.kamal/secrets` : `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `LEDGERFLOW_DATABASE_PASSWORD`, `POSTGRES_PASSWORD` lus dans l'environnement du poste | OK, aucune valeur dans le dépôt |
| Courriel sortant | `config/environments/production.rb` : `raise_delivery_errors = true`, `default_url_options = { host: "example.com" }`, **aucune configuration SMTP** | à faire (§2.3) |
| Courriel entrant (dépôt de pièces) | `action_mailbox.ingress = :relay`, fermé tant qu'aucun mot de passe | à faire (§2.4) |
| Variables d'environnement lues par l'application | voir §2.2 | |
| Identifiants Cloudflare | `docs/cloudflare credentials` (ignoré par git) | à ne jamais committer ; DNS chez Cloudflare |

Le portail s'active seulement si `PORTAL_HOST` est défini (aucune valeur par défaut en production) : **ne pas le définir = pas de portail**. C'est le levier des paliers 1 et 2.

---

## 1. Les trois paliers

| Palier | Contenu | Condition de passage |
|---|---|---|
| **1. Cabinet seul** | Application interne en production (compta, banque, paiements, rapports, signature interne B01/B03). **Portail fermé** (`PORTAL_HOST` absent). Drapeaux `b02a/b02b/b02c` à `false` partout. | Sauvegarde restaurée avec succès, courriel sortant OK, clé de signature en place, supervision en place |
| **2. Portail en bac à sable** | `PORTAL_HOST` défini, rôle PostgreSQL restreint éprouvé, ClamAV, dépôt par courriel SPF+DKIM, **sociétés de test seulement**, personnes de l'équipe comme « clients » | Rôle restreint vérifié, suite portail verte contre ce rôle, parcours complet fait à la main sur un téléphone |
| **3. Ouverture aux clients** | Vrais clients invités | **Test d'intrusion externe passé**, revue du texte juridique par un juriste, revue externe de la cryptographie (B03c), traductions néerlandaises relues, audit mobile réel |

Recommandation : faire le palier 1 d'abord (le plus utile pour vous, aucun risque externe), et ne pas se presser vers les suivants.

---

## 2. Travail à faire dans le dépôt (avant le premier déploiement)

Chaque point : TDD quand il y a du code, un commit par étape cohérente, push seulement sur demande.

### 2.1 Image Docker (`Dockerfile`)
Outils appelés par l'application et **absents** de l'image :
- `ghostscript` (`gs`) : aplatissement des PDF du portail (`PortalAdmin::ReceiveUpload`), filigrane (`Accounting::WatermarkFile`).
- `imagemagick` (`convert`) avec prise en charge **HEIC** (`libheif`/`libheif-plugin-*` selon la distribution) et **règles de sécurité de `policy.xml`** (limiter les formats lus : pas de PS/EPS/PDF/MVG/MSL/URL via ImageMagick ; Ghostscript fait le PDF). Vérifier la ligne `CONVERT_LIMITS` du code.
- `tesseract-ocr` + langues (`fra`, `nld`, `eng` ; voir `Accounting::Extractors::Ocr.languages`).
- `openssl` (déjà présent dans l'image ruby) pour `openssl ts` (horodatage RFC 3161).
- Antivirus : voir §3.4 (client `clamdscan` dans l'image + démon ClamAV en accessoire, ou `clamscan` dans l'image).
- Polices pour les PDF (Prawn utilise ses polices intégrées ; ImageMagick « Helvetica-Bold » demande une police système : `fonts-dejavu-core` ou équivalent).
- **Fixer `ARG RUBY_VERSION=3.3.5`** (ou passer `builder.args` dans `deploy.yml`).
- Vérifier que le build `amd64` fonctionne (`builder.arch: amd64`) et que l'image finale reste raisonnable.
- Ajouter un test statique qui lit le `Dockerfile` et vérifie que chaque binaire externe appelé par le code y figure (comme `spec/static/…`), pour ne plus l'oublier.

### 2.2 Variables d'environnement à ajouter à `config/deploy.yml`
`env.clear` (valeurs non secrètes) et `env.secret` (lues dans `.kamal/secrets`) :

| Variable | Rôle | Palier | Secret ? |
|---|---|---|---|
| `LEDGER_SIGNING_KEY_DIR` | dossier des clés privées de signature (ex. `/rails/signing_keys`), **monté hors `storage`** | 1 | non |
| `MAILER_FROM` | adresse d'envoi (aujourd'hui `from@example.com`) | 1 | non |
| `SMTP_*` (adresse, port, utilisateur, mot de passe, domaine) | courriel sortant (§2.3) | 1 | oui (mot de passe) |
| `APP_HOST` (ou équivalent) | hôte des liens dans les courriels (remplace `example.com`) | 1 | non |
| `RAILS_INBOUND_EMAIL_PASSWORD` | mot de passe du relais Action Mailbox | 2 | oui |
| `DOCUMENTS_MAIL_DOMAIN` | domaine des adresses `documents+<secret>@…` | 2 | non |
| `MAIL_AUTHSERV_ID` | nom que **notre** serveur de courrier écrit en tête d'`Authentication-Results` | 2 | non |
| `PORTAL_HOST` | hôte du portail (ex. `portail.<domaine>`) ; **absent aux paliers 1** | 2 | non |
| `PORTAL_DATABASE_URL` | connexion du rôle restreint du portail | 2 | oui |
| `DOCUMENT_VIRUS_SCAN_COMMAND` (+ `DOCUMENT_VIRUS_SCAN_FAIL_OPEN`, laisser faux) | antivirus sur les pièces | 2 | non |
| `PORTAL_UPLOAD_FILES_PER_DAY`, `PORTAL_UPLOAD_BYTES_PER_MONTH` | quotas globaux (défauts 200 / 2 Go) | 2 | non |
| `B2BROUTER_API_URL`, `DIGITEAL_API_URL`, `ANTHROPIC_API_KEY`, `AGENT_ALLOW_LIVE_PROVIDER`, `AGENT_KILL_SWITCH` | Peppol et agent : **ne les poser que si ces fonctions sont voulues** ; `AGENT_ALLOW_LIVE_PROVIDER` reste absent tant qu'on n'a pas décidé | selon | clé : oui |
| `LEGACY_JWT_ENABLED`, `LEDGERFLOW_JWT_SECRET`, `BUDGETFLOW_*` | intégration BudgetFlow : **fermée par défaut**, ne rien activer sans accord | — | oui |
| `WEBHOOKS_ALLOW_HTTP`, `WEBHOOKS_ALLOW_PRIVATE` | **ne jamais** les mettre en production | — | — |

Aussi : chiffrement Active Record (`encrypts` sur `totp_secret`, pseudonymes de l'agent, etc.) exige les clés `active_record_encryption` dans `config/credentials` : **vérifier qu'elles existent dans les credentials de production** (`bin/rails credentials:show` sur le poste) et que `RAILS_MASTER_KEY` est sauvegardée hors serveur. Sans elles, les secrets TOTP sont illisibles après restauration.

`proxy:` doit lister **les deux hôtes** au palier 2 (`proxy.hosts: [app, portail]`, Kamal 2.11 le permet) — chacun avec son certificat Let's Encrypt.

### 2.3 Courriel sortant (`config/environments/production.rb`)
- Ajouter `config.action_mailer.delivery_method = :smtp` + `smtp_settings` lus dans l'environnement ; `default_url_options` avec le vrai hôte.
- Test : un test de configuration (charge `production.rb` avec des variables factices) pour qu'un hôte `example.com` ne revienne jamais en production.
- Sans SMTP : **les invitations du portail échouent et rien n'est conservé** (le jeton ne passe jamais par une file) ; les résumés quotidiens, rappels, relances de paiement échouent avec une erreur enregistrée.
- Côté DNS du domaine d'envoi : **SPF, DKIM, DMARC** (décision de l'utilisateur : DKIM+SPF stricts). Un fournisseur transactionnel (Postmark, Mailgun, SES, Brevo…) fait le plus gros du travail ; à choisir (§6).

### 2.4 Courriel entrant (dépôt de pièces, palier 2)
Décision déjà prise : SPF **et** DKIM stricts, via **notre propre serveur**. Cela suppose :
1. Un MX pour `DOCUMENTS_MAIL_DOMAIN` vers un serveur de courrier que vous contrôlez (Postfix + `opendkim` + `opendmarc`/`postfix-policyd-spf-python`, ou `rspamd`), **qui écrit un en-tête `Authentication-Results` commençant par le nom `MAIL_AUTHSERV_ID`** et supprime tout `Authentication-Results` venant de l'extérieur.
2. Le transfert vers l'application par le relais Action Mailbox (`bin/rails action_mailbox:ingress:postfix URL=https://<hôte>/rails/action_mailbox/relay/inbound_emails INGRESS_PASSWORD=...`).
3. Attention : beaucoup d'hébergeurs **bloquent le port 25** sortant/entrant. À vérifier avant de choisir où installer ce serveur (peut être une petite VM séparée, pas le serveur de BudgetFlow).
4. Sans cela, tout courriel va en quarantaine : le dépôt par courriel est inutilisable mais rien n'est perdu ni accepté à tort.

### 2.5 Clés de signature (B03c) — volume
- Ajouter à `deploy.yml` : `volumes: - "/var/lib/ledgerflow/signing_keys:/rails/signing_keys"` (dossier **hôte**, créé à la main, `chown 1000:1000`, `chmod 700`) et `LEDGER_SIGNING_KEY_DIR=/rails/signing_keys`.
- Première clé : `bin/kamal app exec "bin/rails integrity:keys:generate"` (voir `lib/tasks/integrity.rake`). **Sans clé : aucun certificat ni aucune preuve d'approbation n'est scellée** (le reste fonctionne).
- La clé privée **n'est ni dans le dépôt, ni dans la base, ni dans les journaux** (règle). Sa sauvegarde est **séparée** de celle de la base (§5) et chiffrée.
- Décider la politique de rotation (QUESTIONS § B03c) et le fournisseur d'horodatage RFC 3161 (§6). Sans fournisseur : pas d'horodatage externe (les ancrages restent chaînés).

### 2.6 Rôle PostgreSQL du portail (palier 2) — jamais éprouvé
- `bin/rails portal:database_role` imprime le SQL (`ROLE=ledgerflow_portal`). Le mot de passe n'y figure pas : le passer en variable psql (`psql -v password=...`, le script contient `PASSWORD :`).
- Exécuter **sur le serveur** (superutilisateur de l'accessoire) sur la base primaire, puis construire `PORTAL_DATABASE_URL=postgres://ledgerflow_portal:<mdp>@ledgerflow-db:5432/ledgerflow_production`.
- **À refaire après chaque migration qui ajoute une table `portal_*`** (le script est généré depuis les tables existantes) — l'ajouter à la liste de contrôle de déploiement (§4) ; envisager une tâche qui compare les droits réels au script (`has_table_privilege`) pour le détecter.
- Vérifier : (1) la page « portail » du cabinet ne dit plus « connexion de l'application » ; (2) lancer la suite portail (`spec/requests/portal`, `spec/static/portal_code_spec.rb`, `direct_access_spec.rb`) **avec `PORTAL_DATABASE_URL` pointant sur un rôle de test** sur une copie de la base (pas sur la production) ; (3) tentative manuelle de `SELECT` sur `accounting_journal_entries` avec ce rôle : doit être refusée.

### 2.8 Adapter `config/deploy.yml` au serveur dédié (code, à faire en premier)
- `servers.web` : nom/IP du nouveau serveur (remplace `budgetflow-production`) ; `accessories.db.host` idem.
- `ssh.user` / `ssh.port` : ceux du nouveau serveur (l'actuel `deploy` / `2221` est celui de BudgetFlow).
- `proxy.host` (puis `proxy.hosts` au palier 2) : le **domaine de l'utilisateur** ; supprimer les commentaires qui parlent de BudgetFlow.
- `accessories.db.port` : `127.0.0.1:5432:5432` ou garder 5433 (aucune raison technique de garder 5433).
- `registry` : confirmer le compte (aujourd'hui Docker Hub `virgostyx`, dépôt `ledgerflow`, privé de préférence).
- Mot de passe PostgreSQL : en générer de nouveaux (`LEDGERFLOW_DATABASE_PASSWORD`, `POSTGRES_PASSWORD`) : le serveur est neuf, **ne rien réutiliser de BudgetFlow**.
- Vérifier avec `bin/kamal config` (affiche la configuration résolue) avant tout `setup`.

### 2.7 Divers dépôt
- `config.hosts` (production.rb) est en commentaire : définir la liste des hôtes autorisés (application + portail).
- IP réelle derrière Cloudflare/kamal-proxy : Rack::Attack et les journaux du portail utilisent l'IP ; configurer les proxys de confiance (`config.action_dispatch.trusted_proxies` avec les plages Cloudflare) **si le proxy orange Cloudflare est utilisé** (§6), sinon toutes les requêtes auront la même IP.
- `config/queue.yml` : écrire un fichier explicite (files `default`, `agent_batch`, nombre de fils) plutôt que de dépendre des défauts ; à la minute, les tâches du portail ne doivent pas affamer les autres.
- Page d'état / `GET /up` déjà présent (`silence_healthcheck_path`). Kamal l'utilise pour le contrôle de santé.
- `bin/ci` (rubocop, brakeman, bundler-audit, importmap audit, tests, seeds) doit être vert avant de construire.
- Tailwind : le build est ignoré par git ; le `Dockerfile` fait `assets:precompile` qui le déclenche — **vérifier que les classes du portail et des nouvelles pages sont bien dans le CSS de l'image** (ouvrir l'écran dans le navigateur).

---

## 3. Travail sur le serveur et chez les fournisseurs

### 3.1 Serveur dédié (préparation)
- Mise en place de base, **avant** `kamal setup` : mises à jour du système, utilisateur de déploiement (clé SSH seulement, mot de passe désactivé, `PermitRootLogin no`), appartenance au groupe `docker` (Kamal installe Docker lui-même s'il manque, mais il lui faut `sudo` ou root pour cela : à décider), synchronisation d'horloge (chrony/systemd-timesyncd : **indispensable**, les horodatages et ancrages en dépendent), fuseau UTC, `unattended-upgrades` pour la sécurité, swap modeste, `fail2ban`.
- Le serveur est vierge : lister quand même l'existant (`docker ps`, `df -h`, `free -h`, ports ouverts) avant toute action.
- Dimensionnement (maintenant pour LedgerFlow seul) : Ghostscript, ImageMagick et Tesseract peuvent consommer plusieurs centaines de Mo de mémoire par document. Prévoir de la marge (RAM, swap) et laisser les limites de ressources déjà dans le code (`CONVERT_LIMITS`, délais d'`ExternalCommand`).
- Pare-feu (ufw ou celui de l'hébergeur) : seuls 80/443 (kamal-proxy), le SSH (port choisi) et, **si** le serveur de courrier est installé ici, 25/587 ; PostgreSQL reste en `127.0.0.1` (le port 5433 n'avait de raison d'être que pour éviter BudgetFlow : on peut revenir à 5432).
- Disque : `ledgerflow_storage` (pièces) et `data` de PostgreSQL ; prévoir l'alerte d'espace.

### 3.2 DNS (Cloudflare — identifiants dans `docs/cloudflare credentials`, ne pas les afficher)
- A : `ledgerflow.budgetflowmanagement.com` (hôte de l'application) → IP du serveur (avant le 1er déploiement, pour Let's Encrypt HTTP-01).
- A : hôte du portail (palier 2), de préférence **sur un domaine distinct** ou au moins un sous-domaine sans cookie partagé (le portail n'utilise pas le cookie de session Rails, mais c'est plus propre).
- MX, SPF, DKIM, DMARC pour le domaine d'envoi et pour `DOCUMENTS_MAIL_DOMAIN` (§2.3, §2.4).
- CAA facultatif (Let's Encrypt).

### 3.3 Certificats
Let's Encrypt via kamal-proxy, un par hôte. Si le proxy orange de Cloudflare est activé, régler le mode SSL de Cloudflare sur « Full (strict) » et décider si l'émission se fait en HTTP-01 derrière le proxy ou avec le proxy temporairement désactivé (§6).

### 3.4 Antivirus (palier 2)
- Option A (recommandée) : conteneur `clamav/clamav` en accessoire Kamal (mise à jour des signatures automatique), `clamdscan` dans l'image, `DOCUMENT_VIRUS_SCAN_COMMAND="clamdscan --fdpass --no-summary -"` ou lecture sur l'entrée standard selon ce que le code attend (l'application passe le fichier **sur l'entrée standard** — vérifier la ligne `config.x.document_virus_scan` et `Accounting::VirusScan`). Accessoire lié au réseau Docker de l'application.
- Option B : `clamscan` dans l'image (lent à chaque lancement, base de signatures dans l'image, à rafraîchir à chaque build).
- Éprouver avec le fichier **EICAR** réel avant ouverture, et vérifier le comportement quand le démon est arrêté (`DOCUMENT_VIRUS_SCAN_FAIL_OPEN` doit rester faux : fichier refusé/laissé en quarantaine).
- Sans antivirus configuré, **tous les fichiers passent** : ne jamais ouvrir le palier 2 sans.

---

## 4. Séquence du premier déploiement (palier 1)

Préalables : §2.1, §2.2 (partie palier 1), §2.3, §2.5, §2.7 faits et poussés ; A record créé ; secrets exportés dans le shell du poste.

1. `bin/ci` vert ; suite complète verte (≈ 65 min, en arrière-plan, seule sur la base de test).
2. Sur le serveur : créer `/var/lib/ledgerflow/signing_keys` (700, propriétaire 1000:1000) ; vérifier l'espace disque.
3. Poser les variables d'environnement du poste (`KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `LEDGERFLOW_DATABASE_PASSWORD`, `POSTGRES_PASSWORD`, `SMTP_*`) **sans les écrire dans un fichier suivi par git**.
4. `bin/kamal setup` (voir §10bis, points 1 et 2 : proxy partagé, délai ; installe Docker si besoin, accessoire PostgreSQL, proxy, première version). Surveiller les journaux ; `db:prepare` crée les 4 bases et charge `structure.sql`.
5. Contrôles : `GET /up`, page de connexion en HTTPS, certificat valide, `bin/kamal app exec "bin/rails db:migrate:status"` (tout « up »), `bin/kamal logs`.
6. Créer le premier utilisateur propriétaire et la première société : voir §7 (le dépôt n'a pas encore de procédure de démarrage en production — à écrire) ; second facteur TOTP obligatoire (`config.x.second_factor_required = true`) : enrôler dès la première connexion.
7. `bin/kamal app exec "bin/rails integrity:keys:generate"` ; vérifier `/.well-known/ledgerflow/keys.json` ; sauvegarder la clé (§5).
8. Envoyer un courriel de test (invitation d'un membre de l'équipe ou relance de test) et vérifier réception, SPF/DKIM/DMARC (outil de test de livraison).
9. Poser le cron de sauvegarde (§5), lancer une sauvegarde, **restaurer vers `ledgerflow_restore_check`** et comparer `SELECT count(*) FROM accounting_journal_entry_lines`.
10. Vérifier que les tâches récurrentes tournent (Solid Queue : `solid_queue_recurring_executions` / `solid_queue_jobs` ; pas d'échecs à la minute pour `PortalAdminJob` — **avec le portail fermé il doit être inoffensif : le vérifier**).
11. Smoke test fonctionnel (liste en §8).
12. Noter la date et la révision déployée (`GIT_REVISION`) dans le journal d'exploitation.

**Retour arrière** : `bin/kamal rollback <version>` ; les migrations sont réversibles mais ne pas rétrograder une migration appliquée sans sauvegarde fraîche ; les journaux d'audit sont immuables (trigger).

**Déploiements suivants** : sauvegarde, `bin/ci`, `bin/kamal deploy`, puis — si une migration a créé une table `portal_*` — re-générer et appliquer le script du rôle du portail (§2.6).

---

## 5. Sauvegardes et reprise (obligatoire avant toute donnée réelle)

| À sauvegarder | Comment | Où |
|---|---|---|
| Base `ledgerflow_production` | `bin/backup` (pg_dump format custom), quotidien | `~/backups` **puis copie hors serveur** |
| Volume `ledgerflow_storage` | `bin/backup` (tgz) | idem |
| **Clés privées de signature** (`/var/lib/ledgerflow/signing_keys`) | copie chiffrée, **séparée** des sauvegardes de la base | gestionnaire de secrets / coffre hors ligne |
| `RAILS_MASTER_KEY`, credentials, clés `active_record_encryption` | gestionnaire de mots de passe | hors serveur |
| Configuration serveur (DNS, Postfix/DKIM, `deploy.yml`, scripts) | dépôt (sans secrets) + notes | |

- Les bases cache/queue/cable se reconstruisent ; ne pas les sauvegarder.
- **Copie hors serveur non faite** : choisir la destination (rclone vers stockage objet européen chiffré, ou un second serveur) — décision à prendre (§6). Une sauvegarde sur la même machine ne protège pas de la perte du serveur.
- **Perte d'une clé de signature** : les certificats déjà émis restent vérifiables (clé publique dans la base et publiée), mais on ne peut plus en signer avec cette clé ; générer une nouvelle clé, ne rien réécrire.
- Planifier un **exercice de restauration** trimestriel et noter le résultat. Objectifs à fixer avec vous : RPO (perte de données acceptable, par défaut 24 h avec la sauvegarde nocturne ; envisager l'archivage WAL si moins) et RTO.

---

## 6. Décisions à prendre (je recommande par défaut, vous tranchez)

| # | Question | Recommandation par défaut |
|---|---|---|
| 1 | Fournisseur de courriel sortant (l'adresse e-mail de l'utilisateur sert-elle d'expéditeur ? chez quel hébergeur de domaine/courrier ?) | fournisseur transactionnel européen, DKIM propre au domaine, DMARC en `p=quarantine` après observation |
| 2 | Où installer le serveur de courrier entrant (port 25, DKIM/SPF) | possible sur le serveur dédié **si l'hébergeur ouvre le port 25** ; sinon petite VM séparée. Le garder isolé de l'application (conteneur ou machine à part) reste préférable |
| 3 | Cloudflare en mode proxy (orange) ou DNS seul (gris) | DNS seul au début (moins de pièges Let's Encrypt/IP réelle) ; passer au proxy plus tard avec les plages de confiance |
| 4 | Domaine du portail | domaine distinct de l'application cabinet |
| 5 | Destination de la copie de sauvegarde hors serveur | stockage objet chiffré européen via rclone, rétention 30 jours + mensuelles |
| 6 | Fournisseur d'horodatage RFC 3161 | à choisir (qualifié eIDAS si la valeur juridique est visée) ; aucun par défaut |
| 7 | Un environnement de recette (staging) ? | oui, au minimum une seconde instance éphémère sur un autre hôte avant le palier 2 |
| 8 | Antivirus : conteneur ClamAV accessoire ou `clamscan` dans l'image | conteneur accessoire |
| 9 | Politique de rotation des clés de signature | une clé active, rotation annuelle ou sur incident, anciennes clés conservées publiques |
| 10 | Supervision : outil de disponibilité + alertes (courriel/SMS) | contrôle externe sur `/up` + alerte d'espace disque + alerte si une tâche récurrente n'a pas tourné |
| 11 | Pare-feu/Fail2ban sur le serveur | oui (SSH sur 2221, limiter) |
| 12 | Peppol (B2Brouter/Digiteal) et agent (Anthropic) en production maintenant ? | non tant que non demandé ; garder les clés absentes |

---

## 7. Démarrage fonctionnel (à préparer, rien n'est écrit)

- Procédure de création du premier utilisateur et de la première société en production (pas de `db:seed` à lancer en production sans relecture : vérifier ce que font les seeds et ne jamais lancer `db:seed:replant`, qui efface).
- Plan comptable (PCMN) et paramétrage de base d'une société réelle : voir les écrans Settings.
- Drapeaux de société : tous les drapeaux `b0x`/`f0x` sont **par société** (`entities.features`), faux par défaut hors tests. Les activer société par société, `b02a` et suivants seulement au palier 2.
- Reprise de données éventuelle (import d'écritures, extraits bancaires) : procédure à décrire séparément.

---

## 8. Liste de contrôle après déploiement (smoke tests)

Palier 1 :
- Connexion + second facteur TOTP, déconnexion.
- Création d'une écriture, validation (`entries.post`), grand livre, balance, bilan (R07/R08).
- Import d'un extrait bancaire, lettrage.
- Lot de paiement : brouillon → approbation → fichier pain.001 (vérifier qu'il est identique octet pour octet à la régénération) — **aucun paiement n'est initié par l'application**.
- Page « Intégrité » : auto-contrôle C23 vert ; émettre un certificat ; ouvrir `/verify/:uuid` ; vérifier avec `tools/ledger-verify` hors application.
- Courriel de test reçu (SPF/DKIM/DMARC « pass »).
- Une tâche récurrente s'exécute (consulter les files).
- Sauvegarde + restauration de test.

Palier 2 (en plus) :
- Invitation d'une personne de l'équipe sur le portail, TOTP, appareil nouveau → alerte.
- Publication d'un rapport (R07+R08), lecture côté client, accusé.
- Téléversement d'une photo (HEIC), d'un PDF, d'un fichier EICAR (doit être refusé) ; envoi hors ligne avec le service worker ; reprise après coupure.
- Dépôt par courriel : message avec SPF+DKIM valides accepté, message falsifié en quarantaine.
- Question → réponse → synchronisation ; message ; **approbation des comptes avec code TOTP** (le code de secours doit être refusé) ; preuve scellée (suppose la clé).
- Rôle restreint : le portail ne peut pas lire la comptabilité (tentative directe refusée).
- Aucun accès croisé entre sociétés (`direct_access_spec`).

---

## 9. Hors code, avant le palier 3 (ouverture aux clients)

1. **Test d'intrusion externe** (critère 13 de la spec) : doit couvrir fichiers téléversés, réponses, messages, approbations, courriel entrant, rôle PostgreSQL.
2. **Revue du texte juridique** de l'approbation par un juriste (`Portal::ApprovalText`, version `2026-10-draft-1`, fr/nl/en) ; traductions néerlandaises relues par un néerlandophone ; pages B02a/B02b encore **en anglais seulement**.
3. **Revue externe de la cryptographie** de B03c (couvre aussi les preuves d'approbation B02c).
4. Audit d'accessibilité et de performance sur **vrais téléphones** (B02b).
5. Conservation des messages du portail : 10 ans (documenté, aucune purge codée) — à valider avec un référent juridique.
6. Politique de confidentialité / mentions, registre RGPD (traitement de documents clients), procédure d'incident, contrat de sous-traitance avec les fournisseurs (courriel, stockage, horodatage).
7. Procédure d'urgence : couper le portail (retirer `PORTAL_HOST` et redéployer, ou drapeau `b02a` à faux par société), révoquer les droits, rotation des clés.

---

## 10. Pièges déjà connus (à ne pas redécouvrir)

- Ne jamais lancer deux `rspec` à la fois ; ne jamais `pgrep -f rspec` dans une boucle d'attente (utiliser `tail --pid=<pid> -f /dev/null`).
- L'utilisateur de la base de test n'est pas superutilisateur : la production, oui côté accessoire — ne pas confondre.
- Les migrations ne doivent pas avoir un horodatage dans le futur de l'horloge de la machine.
- `config.i18n.fallbacks` est `[:en]` dans `application.rb` mais `true` dans `production.rb` : vérifier l'effet réel en production sur le portail (locale `fr`/`nl` sans clé).
- Le Tailwind compilé n'est pas dans git : reconstruit à chaque build d'image.
- L'agent d'outils a une limite de 34 000 octets pour le catalogue (`tool_catalog_spec`).
- Un fichier écrit en Python avec `open(p,'w')` avant lecture est tronqué.

---

## 10bis. Spécificités Kamal (2.11, vérifiées dans la gem)

Le déploiement se fait avec Kamal ; ces règles s'ajoutent aux §2 à §5.

1. **(Allégé : le serveur est maintenant dédié.)** Le proxy était partagé avec BudgetFlow ; si BudgetFlow ou une autre application rejoint un jour ce serveur, les règles ci-dessous redeviennent obligatoires. **Ancien texte :** `kamal setup` démarre le proxy s'il n'existe pas ; `kamal proxy reboot|upgrade|remove|stop|restart` l'agit pour **toutes** les applications du serveur. Règles : (a) comparer la version de Kamal / de `kamal-proxy` de BudgetFlow et de LedgerFlow avant le premier `setup` ; (b) après le premier déploiement, n'utiliser que `kamal deploy`, `kamal rollback`, `kamal app ...`, `kamal accessory ...`, `kamal logs` ; (c) **aucune commande `kamal proxy ...` ni `kamal upgrade` sans accord explicite** ; (d) un hook `pre-proxy-reboot` (`.kamal/hooks/`) qui refuse (`exit 1`) protège contre l'accident.
2. **Premier démarrage lent.** `deploy_timeout` vaut 30 s et `readiness_delay` 7 s par défaut. Le premier conteneur fait `db:prepare` (création des 4 bases + chargement de `structure.sql`). Mettre `deploy_timeout: 120` au premier déploiement, puis le réduire ; si le conteneur est tué avant la fin, relancer `kamal deploy` est sans danger (`db:prepare` est idempotent).
3. **Migrations pendant un déploiement sans coupure.** Le nouveau conteneur migre au démarrage alors que l'ancien sert encore sur le nouveau schéma. Règle pour chaque migration : compatible avec le code précédent (ajouter avant d'utiliser, ne jamais renommer ni supprimer une colonne dans le même déploiement : deux étapes). `kamal rollback <version>` remet l'ancienne image mais **ne défait pas les migrations** ; si une migration doit être défaite, sauvegarde fraîche puis `bin/rails db:rollback` via `kamal app exec`. Les tâches récurrentes peuvent brièvement tourner dans deux conteneurs : Solid Queue les dédoublonne (une exécution par échéance).
4. **IP réelle.** Avec `proxy.ssl: true`, kamal-proxy **n'accepte plus** les en-têtes `X-Forwarded-*` venant de l'extérieur sauf `proxy.forward_headers: true`. Sans proxy Cloudflare (DNS gris) : rien à faire, le proxy écrit la bonne IP. Avec le proxy orange de Cloudflare : l'IP vue serait celle de Cloudflare ; il faut soit `forward_headers: true` + plages Cloudflare de confiance (`trusted_proxies`), soit lire `CF-Connecting-IP`. Rack::Attack, les journaux du portail et les alertes de connexion en dépendent : à tester par une requête de contrôle avant le palier 2.
5. **Hooks (`.kamal/hooks/`, aujourd'hui seulement des `.sample`).** Proposés : `pre-build` (refuse si l'arbre git n'est pas propre ou si `bin/ci` échoue), `pre-deploy` (lance `bin/backup` sur le serveur via SSH et refuse de déployer si la sauvegarde échoue), `post-deploy` (affiche la révision déployée et vérifie `GET /up`). Un hook qui échoue arrête le déploiement : c'est voulu.
6. **Accessoires.** `kamal setup` démarre l'accessoire `db` ; ensuite : `kamal accessory details db`, `kamal accessory logs db`, `kamal accessory exec db "psql -U ledgerflow -d ledgerflow_production"` (création du rôle du portail, §2.6), `kamal accessory reboot db` (coupe la base : jamais sans sauvegarde ni accord). Les `directories` d'un accessoire sont créés sous le dossier de données du service sur l'hôte (chemin relatif = sous le répertoire personnel de l'utilisateur `deploy`, vérifier avec `ls` sur le serveur) : c'est ce chemin que `bin/backup` et la procédure de restauration doivent connaître. Ajout d'un accessoire (ClamAV, §3.4) : bloc `accessories:` + `kamal accessory boot clamav`, nom d'hôte Docker = `<service>-<nom>` (comme `ledgerflow-db` pour `DB_HOST`).
7. **Ajouter un secret.** Trois endroits, dans l'ordre : le déclarer dans `.kamal/secrets` (qui lit l'environnement du poste ou un gestionnaire, **jamais de valeur en clair**), le lister dans `env.secret` de `deploy.yml`, l'exporter dans le shell avant `kamal deploy`. Un secret listé mais absent de l'environnement fait échouer le déploiement (c'est utile). Changer une valeur secrète demande un `kamal deploy` (ou `kamal app boot`) pour la propager.
8. **Volume des clés de signature.** `volumes:` avec un chemin absolu côté hôte (`/var/lib/ledgerflow/signing_keys:/rails/signing_keys`) est un montage direct : créé à la main avant (Docker le créerait en `root` sinon), propriétaire `1000:1000`. `kamal app exec` (sans `--reuse`) démarre un conteneur neuf **avec les mêmes volumes et variables** : c'est la bonne commande pour `integrity:keys:generate` ; les alias `console`/`shell` utilisent `--reuse` (conteneur en marche).
9. **Un seul hôte, un seul rôle `web`.** Les tâches récurrentes tournent dans Puma (`SOLID_QUEUE_IN_PUMA`). Si la charge des tâches du portail (à la minute) gêne les requêtes, créer un rôle `job` sur le même hôte (`servers.job` avec `cmd: bin/jobs`) et retirer `SOLID_QUEUE_IN_PUMA` du rôle web ; décision différée, pas nécessaire au palier 1.
10. **Commandes utiles** : `kamal config` (affiche la configuration résolue : à lancer après chaque modification de `deploy.yml`), `kamal lock status|release` (verrou de déploiement bloqué), `kamal audit` (historique des opérations), `kamal app version`, `kamal app containers`, `kamal prune all` (nettoyage des anciennes images : accord préalable, le serveur est partagé).

## 10ter. Décisions prises le 2026-10-17 (palier 1)

- Hôte de l'application : `app.ledgerflowmanagment.com` (sans « e » : c'est l'orthographe du domaine enregistré). DNS Cloudflare **seul** (nuage gris). Serveur `2.24.163.249`, Ubuntu 26.04, SSH `deploy` port 2222. Registre : Docker Hub privé `virgostyx/ledgerflow`.
- Courriel sortant : SMTP Hostinger (`smtp.hostinger.com:465`, TLS implicite), expéditeur `no-reply@ledgerflowmanagment.com`. Enregistrements MX/SPF/DKIM de Hostinger à recopier dans Cloudflare.
- Sauvegarde hors serveur : OVH Object Storage (S3), `rclone crypt`, `bin/backup-offsite` ; verrouillage d'objet recommandé. Supervision : contrôle externe de `/up` + `bin/watch`.
- Horodatage RFC 3161 : **absent** au palier 1.
- Brakeman : 34 avertissements antérieurs, dont 4 de confiance haute examinés et jugés faux positifs (voir l'historique) ; reste rouge, traitement différé. `bin/brakeman` impose `--ensure-latest` (8.1.0 disponible, dépôt en 8.0.4).
- Création de compte libre fermée en production (`OPEN_SIGNUP`), premier administrateur par `users:create_owner`, données de référence par `reference:load` : voir `production_start.md`.

## 11. Premier message suggéré pour la nouvelle session

> Lis `docs/dev/DEPLOYMENT_PLAN.md`, `config/deploy.yml`, `Dockerfile`, `docs/dev/backup_restore.md`. Nous visons le **palier 1** (cabinet seul, portail fermé). Commence par le §2 : propose-moi, point par point (2.1 Dockerfile, 2.2 variables, 2.3 SMTP, 2.5 volume des clés, 2.7 divers), les changements, en TDD quand c'est du code. Ne touche pas au serveur ni à BudgetFlow sans mon accord, ne committe pas de secret, ne pousse pas sans que je le demande. Pose-moi les questions du §6 dont tu as besoin avant de coder.

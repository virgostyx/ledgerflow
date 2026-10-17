# Préparation du serveur dédié (palier 1)

Serveur : `2.24.163.249`, Ubuntu 26.04.1, 1 vCPU, 3,8 Gio de RAM, utilisateur `deploy` (groupes `sudo` et `docker`), SSH sur le **port 22** (décision du 2026-10-17 : on ne le déplace pas). À faire **avant** `bin/kamal setup`.

Inventaire du 2026-10-17 : Docker 29.9.1 est déjà installé, l'horloge est en UTC et synchronisée, il n'y a pas de swap, et `sudo` demande un mot de passe : les étapes avec `sudo` se font dans une **session SSH interactive** (`ssh deploy@2.24.163.249`), pas en commande passée en une ligne.

> **Rien de ce fichier n'a été exécuté.** Les commandes sont à relire puis à lancer par vous (ou à me faire lancer, une par une, avec votre accord). Elles sont écrites pour Ubuntu ; les noms de paquets et de services de **26.04 n'ont pas été vérifiés** (version récente) : en cas d'écart, `apt search` / `systemctl status` tranche.
> Ne fermez jamais la session SSH ouverte avant d'avoir testé une **seconde** connexion (§2, §3).

## État du serveur au 2026-10-17 (fait, vérifié sur place)

- Ubuntu 26.04.1, 1 vCPU, 3,8 Gio de RAM, disque 48 Go ; UTC, horloge synchronisée ; Docker 29.9.1 ; `deploy` dans les groupes `sudo` et `docker`.
- SSH sur le port 22 ; `PermitRootLogin no`, `AllowUsers deploy`, `MaxAuthTries 3` ; **mot de passe SSH fermé** par `/etc/ssh/sshd_config.d/00-hardening.conf` (le fichier `50-cloud-init.conf` forçait `yes` et passait avant le fichier principal) ; contrôle fait : la connexion sans clé est refusée.
- `ufw` actif : 22, 80, 443 ouverts (IPv4 et IPv6), le reste refusé. `fail2ban` : jails `sshd` et `recidive`. `unattended-upgrades` activé.
- Postfix (livré avec l'image de l'hébergeur) : `inet_interfaces = loopback-only`, plus rien sur le port 25 de l'extérieur. Pour un courrier entrant un jour (palier 2) : remettre `all` et ouvrir le port dans `ufw`.
- `monarx-agent` écoute sur `127.0.0.1:65529` : agent de sécurité de l'hébergeur, laissé en place.
- Swap de 2 Gio (`/swapfile`, dans `/etc/fstab`).
- `/var/lib/ledgerflow/signing_keys` créé (700, uid/gid 1000).

- Réseau : l'enregistrement A `app.ledgerflowmanagment.com` → `2.24.163.249` répond (1.1.1.1 et 8.8.8.8). **Un port sans service expire au lieu de répondre « refusé »** sur cette plateforme (constaté sur 80 et 443) : ce n'est ni `ufw` (les compteurs montrent les paquets acceptés) ni un blocage ; avec un service à l'écoute, le port 80 répond (testé avec un serveur temporaire de 60 s). Le port 443 sera confirmé par le premier `https://` après `kamal setup`.

Les sections 2 à 6 ci-dessous restent la référence ; ce qui est déjà fait y est à ignorer.

## 1. Voir ce qui existe (lecture seule)

```
ssh deploy@2.24.163.249
lsb_release -a; uname -r; id
df -h; free -h; nproc
sudo ss -tlnp            # ports ouverts
docker ps 2>&1 | head -3 # Docker déjà là ?
timedatectl              # fuseau et synchronisation d'horloge
sudo -l                  # droits sudo de deploy
```

## 2. Système, heure, SSH

```
sudo apt update && sudo apt upgrade -y
timedatectl show -p NTPSynchronized     # yes : déjà vérifié le 2026-10-17, fuseau UTC (les horodatages et ancrages en dépendent)
sudo apt install -y unattended-upgrades fail2ban ufw curl
sudo dpkg-reconfigure -plow unattended-upgrades
```

Vérifier la configuration SSH **réelle** (sans la modifier) :

```
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)'
```

Attendu : `port 22`, `permitrootlogin no`, `passwordauthentication no`, `pubkeyauthentication yes`. Si ce n'est pas le cas, corriger dans `/etc/ssh/sshd_config.d/` puis `sudo sshd -t && sudo systemctl reload ssh`, et **tester une seconde connexion** avant de fermer la première.

## 3. Pare-feu et fail2ban

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH : AVANT d'activer
sudo ufw allow 80/tcp       # Let's Encrypt et redirection
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

PostgreSQL est publié sur `127.0.0.1:5432` seulement (voir `deploy.yml`). Docker contourne `ufw` pour les ports publiés, ce qui est sans conséquence ici puisque seul kamal-proxy (80/443) est publié sur toutes les interfaces.

```
sudo tee /etc/fail2ban/jail.d/ssh.local <<'EOF'
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 1h
EOF
sudo systemctl restart fail2ban && sudo fail2ban-client status sshd
```

## 4. Mémoire

Ghostscript, ImageMagick et Tesseract consomment de la mémoire par document. `free -h` du 2026-10-17 : 3,8 Gio de RAM et **0 de swap**, donc à faire :

```
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 5. Docker

**Déjà fait** (Docker 29.9.1, `deploy` dans le groupe `docker`). Contrôle seulement : `docker run --rm hello-world`. Kamal n'a besoin ni de `root` ni de `sudo` sans mot de passe.

## 6. Dossier des clés de signature

L'utilisateur du conteneur est `1000:1000` (voir `Dockerfile`). Le dossier appartient à ce numéro, pas à `deploy` (dont l'uid peut différer : `id deploy`).

```
sudo install -d -o 1000 -g 1000 -m 700 /var/lib/ledgerflow/signing_keys
ls -ld /var/lib/ledgerflow/signing_keys
```

La clé privée n'est créée qu'après le premier déploiement (`bin/kamal app exec "bin/rails integrity:keys:generate"`). Sa sauvegarde est séparée de celle de la base (§ « Clés » de `backup_restore.md`).

## 7. Scripts de sauvegarde et de supervision

Le dépôt n'est **pas** sur le serveur (Kamal déploie une image). Les trois scripts se copient à la main, et sont à recopier quand ils changent :

```
# depuis le poste
scp bin/backup bin/backup-offsite bin/watch deploy@2.24.163.249:~/bin/
ssh deploy@2.24.163.249 'chmod 700 ~/bin/backup ~/bin/backup-offsite ~/bin/watch'
```

(`mkdir -p ~/bin` d'abord si besoin.) Les tâches planifiées sont décrites dans `backup_restore.md`.

## 8. Contrôle avant `bin/kamal setup`

- [ ] `ssh deploy@2.24.163.249` fonctionne par clé, deuxième connexion testée
- [ ] `timedatectl` : UTC, synchronisée
- [ ] `sudo ufw status` : 22, 80, 443
- [ ] `docker run --rm hello-world` sous `deploy`
- [ ] `/var/lib/ledgerflow/signing_keys` : `drwx------ 1000 1000`
- [ ] enregistrement A `app.ledgerflowmanagment.com` → `2.24.163.249` (DNS seul), résolu depuis votre poste
- [ ] ports 80 et 443 joignables de l'extérieur (hébergeur)
- [ ] variables exportées dans le shell du poste : `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `LEDGERFLOW_DATABASE_PASSWORD`, `POSTGRES_PASSWORD`, `SMTP_PASSWORD`
- [ ] `bin/kamal config` sans erreur (affiche la configuration résolue)

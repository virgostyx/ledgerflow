# Préparation du serveur dédié (palier 1)

Serveur : `2.24.163.249`, Ubuntu 26.04, utilisateur `deploy`, SSH sur le port 2222. À faire **avant** `bin/kamal setup`.

> **Rien de ce fichier n'a été exécuté.** Les commandes sont à relire puis à lancer par vous (ou à me faire lancer, une par une, avec votre accord). Elles sont écrites pour Ubuntu ; les noms de paquets et de services de **26.04 n'ont pas été vérifiés** (version récente) : en cas d'écart, `apt search` / `systemctl status` tranche.
> Ne fermez jamais la session SSH ouverte avant d'avoir testé une **seconde** connexion (§2, §3).

## 1. Voir ce qui existe (lecture seule)

```
ssh -p 2222 deploy@2.24.163.249
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
sudo timedatectl set-timezone UTC
timedatectl show -p NTPSynchronized     # doit dire yes (les horodatages et ancrages en dépendent)
sudo apt install -y unattended-upgrades fail2ban ufw curl
sudo dpkg-reconfigure -plow unattended-upgrades
```

Vérifier la configuration SSH **réelle** (sans la modifier) :

```
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)'
```

Attendu : `port 2222`, `permitrootlogin no`, `passwordauthentication no`, `pubkeyauthentication yes`. Si ce n'est pas le cas, corriger dans `/etc/ssh/sshd_config.d/` puis `sudo sshd -t && sudo systemctl reload ssh`, et **tester une seconde connexion** avant de fermer la première.

## 3. Pare-feu et fail2ban

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp     # SSH : AVANT d'activer
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
port = 2222
maxretry = 5
bantime = 1h
EOF
sudo systemctl restart fail2ban && sudo fail2ban-client status sshd
```

## 4. Mémoire

Ghostscript, ImageMagick et Tesseract consomment de la mémoire par document. Si `free -h` montre moins de 2 Go de swap :

```
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 5. Docker

Kamal installe Docker s'il manque, mais il lui faut alors `root` ou `sudo` sans mot de passe. Plus simple et plus sûr : l'installer vous-même, et donner le groupe `docker` à `deploy`.

```
sudo apt install -y docker.io          # ou le dépôt officiel Docker si docker.io est absent de 26.04
sudo usermod -aG docker deploy         # puis se reconnecter
docker version && docker run --rm hello-world
```

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
scp -P 2222 bin/backup bin/backup-offsite bin/watch deploy@2.24.163.249:~/bin/
ssh -p 2222 deploy@2.24.163.249 'chmod 700 ~/bin/backup ~/bin/backup-offsite ~/bin/watch'
```

(`mkdir -p ~/bin` d'abord si besoin.) Les tâches planifiées sont décrites dans `backup_restore.md`.

## 8. Contrôle avant `bin/kamal setup`

- [ ] `ssh -p 2222 deploy@2.24.163.249` fonctionne par clé, deuxième connexion testée
- [ ] `timedatectl` : UTC, synchronisée
- [ ] `sudo ufw status` : 2222, 80, 443
- [ ] `docker run --rm hello-world` sous `deploy`
- [ ] `/var/lib/ledgerflow/signing_keys` : `drwx------ 1000 1000`
- [ ] enregistrement A `app.ledgerflowmanagment.com` → `2.24.163.249` (DNS seul), résolu depuis votre poste
- [ ] ports 80 et 443 joignables de l'extérieur (hébergeur)
- [ ] variables exportées dans le shell du poste : `KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`, `LEDGERFLOW_DATABASE_PASSWORD`, `POSTGRES_PASSWORD`, `SMTP_PASSWORD`
- [ ] `bin/kamal config` sans erreur (affiche la configuration résolue)

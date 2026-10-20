# Sauvegarde et restauration (production)

Production : Kamal, un PostgreSQL 16 en accessoire (`ledgerflow-db`, serveur dédié `2.24.163.249`), volume `ledgerflow_storage` pour les fichiers, clés de signature dans `/var/lib/ledgerflow/signing_keys` (hôte).

## Ce qu'il faut sauvegarder

| Élément | Où | Pourquoi |
|---|---|---|
| `ledgerflow_production` | conteneur `ledgerflow-db` | toute la comptabilité |
| volume `ledgerflow_storage` | `/rails/storage` | fichiers téléversés |
| **clés privées de signature** | `/var/lib/ledgerflow/signing_keys` | sans elles on ne peut plus sceller de certificat. Copie chiffrée, **séparée** des sauvegardes de la base (jamais dans le même lieu), par exemple `tar czf - -C /var/lib/ledgerflow signing_keys \| age -r <clé publique> > signing_keys.tgz.age` puis stockage hors ligne |
| `RAILS_MASTER_KEY`, `config/credentials`, clés de chiffrement Active Record | hors serveur (gestionnaire de mots de passe) | sans elles, les données chiffrées (identifiants Peppol) sont illisibles après restauration |

Les bases `cache`, `queue` et `cable` se reconstruisent : inutile de les sauvegarder.

## Sauvegarde

`bin/backup` (à lancer sur le serveur, utilisateur `deploy`) écrit `db-AAAAMMJJ-HHMMSS.dump` (pg_dump au format custom) et `storage-....tgz` dans `~/backups`, puis supprime ce qui a plus de 30 jours (`BACKUP_DIR`, `KEEP_DAYS` réglables).

Les scripts sont copiés sur le serveur (le dépôt n'y est pas) : voir `server_preparation.md` §7.

**Copie hors serveur (`bin/backup-offsite`)** : `rclone copy` vers un bucket OVH Object Storage (S3) **chiffré** (remote `crypt` d'rclone), sans jamais réécrire un objet (`--immutable`), puis `rclone check` (taille). Garde 30 jours de copies quotidiennes et, le 1er de chaque mois, une copie `monthly/` qui n'est jamais supprimée. Le verrouillage d'objet du bucket empêche d'effacer une copie pendant sa période : le nettoyage affiche alors un avertissement et réessaie le lendemain.

Configuration rclone, **à faire sur le serveur, jamais dans le dépôt ni dans le chat** (`rclone config`, fichier `~/.config/rclone/rclone.conf` en mode 600) :
1. remote S3 `ovh` : fournisseur `Other` (ou `OVHcloud` si proposé), `endpoint` de la région du bucket (`s3.gra.io.cloud.ovh.net` pour Gravelines, `s3.sbg.io.cloud.ovh.net` pour Strasbourg : à confirmer dans la console OVH), clé d'accès et secret de l'utilisateur S3 dédié ;
2. remote `ledgerflow-offsite` de type `crypt`, `remote = ovh:<nom-du-bucket>`, mot de passe et sel (`password2`) **générés** et rangés dans votre gestionnaire de mots de passe : sans eux, les copies sont illisibles ;
3. essai : `rclone lsd ledgerflow-offsite:` puis une copie d'un petit fichier.

Planification (`crontab -e`, utilisateur `deploy`) :
```
30 2 * * * $HOME/bin/backup && $HOME/bin/backup-offsite >> $HOME/backup.log 2>&1
17 * * * * $HOME/bin/watch > /dev/null
```
`bin/watch` surveille le disque, l'âge de la dernière sauvegarde locale et hors serveur, et les tâches récurrentes ; il envoie un courriel (au plus un toutes les 12 h) avec les identifiants de `~/.ledgerflow-watch.env` (mode 600, créé à la main : `ALERT_SMTP_URL=smtps://smtp.hostinger.com:465`, `ALERT_USER`, `ALERT_PASSWORD`, `ALERT_TO`). La requête sur les tâches récurrentes (`solid_queue_recurring_executions` dans `ledgerflow_production_queue`) est à **valider sur le serveur** au premier déploiement.

## État au 2026-10-18 (fait, vérifié sur le serveur)

- Bucket OVH `fragile-estrin` (région Paris, `eu-west-par`, endpoint `s3.eu-west-par.io.cloud.ovh.net`), **verrouillage d'objet désactivé** : qui possède les clés S3 peut effacer les copies. À réévaluer (un bucket avec verrouillage se choisit à la création) avant d'y mettre des archives de 7 ans.
- rclone 2 remotes dans `/home/deploy/.config/rclone/rclone.conf` (600, utilisateur `deploy`) : `ovh` (S3) et `ledgerflow-offsite` (crypt, mot de passe et sel rangés dans le gestionnaire de mots de passe). Piège rencontré : un `rclone config` lancé en `root` écrit dans `/root/.config/rclone/` ; le cron et les scripts lisent le fichier de `deploy`. Se déplace par `install -m 600 -o deploy -g deploy` depuis `root`, sans retaper les clés, puis on efface la copie de `root`.
- `rclone check` d'un remote crypt ne compare que les **tailles** (« No common hash found ») : un envoi tronqué se voit, un octet altéré non. Amélioration prévue : `rclone cryptcheck`.
- Restauration essayée sur le serveur le 2026-10-18 dans `ledgerflow_restore_check` : mêmes comptes (lignes d'écriture, utilisateurs, sociétés) que la production ; base de test supprimée ensuite.
- `~/bin/watch` : `ok`, et courriel d'alerte reçu avec `WATCH_DISK_MAX=1` ; la requête sur `solid_queue_recurring_executions` est validée.
- `cron` de `deploy` : `30 2 * * *` (sauvegarde puis copie hors serveur, UTC) et `17 * * * *` (`watch`).
- Clé de signature `lk-20261018-d75052c7` (Ed25519, active, empreinte `dd31f7a2…d69979`) : créée le 2026-10-18, publiée sur `/.well-known/ledgerflow/keys.json` (vérifié le 2026-10-20), drapeau `b03c` coché. Le fichier privé (PEM de 119 octets) est copié **dans une note sécurisée du gestionnaire de mots de passe**, hors serveur, séparé de la base et du bucket OVH (pas d'`age` : inutile pour 119 octets). Lecture : `ssh deploy@… 'cat /var/lib/ledgerflow/signing_keys/<key_id>.pem'`. Après une rotation (`integrity:keys:rotate`), ranger aussi la nouvelle clé et **garder l'ancienne** (les certificats déjà scellés se vérifient avec sa clé publique).
- L'archive `storage-*.tgz` appartient à `root` (le conteneur `alpine` tourne en root) : sans conséquence, `deploy` la lit et la supprime dans son dossier.

## Restauration

1. Arrêter l'application : `kamal app stop`.
2. Créer une base vide et restaurer (depuis le serveur) :
   ```
   docker exec ledgerflow-db psql -U ledgerflow -d postgres -c "DROP DATABASE IF EXISTS ledgerflow_production"
   docker exec ledgerflow-db psql -U ledgerflow -d postgres -c "CREATE DATABASE ledgerflow_production"
   docker exec -i ledgerflow-db pg_restore -U ledgerflow -d ledgerflow_production --no-owner < ~/backups/db-AAAAMMJJ-HHMMSS.dump
   ```
3. Fichiers : `docker run --rm -v ledgerflow_storage:/data -v ~/backups:/in alpine sh -c "cd /data && tar xzf /in/storage-AAAAMMJJ-HHMMSS.tgz"`.
4. Redémarrer : `kamal app boot`, puis `kamal app exec "bin/rails db:migrate:status"` pour vérifier.

## Vérification (à répéter régulièrement)

Une sauvegarde qui n'a jamais été restaurée n'est pas une sauvegarde. Le cycle dump → restauration dans une base vide a été vérifié en local (même nombre de lignes comptables avant et après). **Non vérifié sur le serveur de production** : à faire une première fois vers une base de test (`ledgerflow_restore_check`), en comparant `SELECT count(*) FROM accounting_journal_entry_lines`.

Les journaux d'audit sont immuables (trigger sur UPDATE/DELETE) : la restauration par `pg_restore` les recharge sans problème, mais un `DELETE` manuel échouera.

## À décider

- ~~Destination de la copie hors serveur~~ : décidée le 2026-10-17, OVH Object Storage chiffré avec rclone (quotidienne).
- Durée de conservation légale : la comptabilité belge se conserve 7 ans ; `KEEP_DAYS=30` ne suffit pas pour les archives. Prévoir une sauvegarde annuelle conservée séparément (par exemple après chaque clôture d'exercice).

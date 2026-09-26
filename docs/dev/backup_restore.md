# Sauvegarde et restauration (production)

Production : Kamal, un PostgreSQL 16 en accessoire (`ledgerflow-db`, hôte `budgetflow-production`), volume `ledgerflow_storage` pour les fichiers.

## Ce qu'il faut sauvegarder

| Élément | Où | Pourquoi |
|---|---|---|
| `ledgerflow_production` | conteneur `ledgerflow-db` | toute la comptabilité |
| volume `ledgerflow_storage` | `/rails/storage` | fichiers téléversés |
| `RAILS_MASTER_KEY`, `config/credentials`, clés de chiffrement Active Record | hors serveur (gestionnaire de mots de passe) | sans elles, les données chiffrées (identifiants Peppol) sont illisibles après restauration |

Les bases `cache`, `queue` et `cable` se reconstruisent : inutile de les sauvegarder.

## Sauvegarde

`bin/backup` (à lancer sur le serveur, utilisateur `deploy`) écrit `db-AAAAMMJJ-HHMMSS.dump` (pg_dump au format custom) et `storage-....tgz` dans `~/backups`, puis supprime ce qui a plus de 30 jours (`BACKUP_DIR`, `KEEP_DAYS` réglables).

Planification, par exemple `crontab -e` : `30 2 * * * /chemin/vers/ledgerflow/bin/backup >> ~/backup.log 2>&1`.

**Copie hors serveur (à faire, non automatisée)** : une sauvegarde sur la même machine ne protège pas d'une panne du serveur. Copier `~/backups` vers un autre lieu (rsync, rclone vers un stockage objet) après chaque exécution. Le choix du stockage est une décision à prendre.

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

- Destination de la copie hors serveur et fréquence (quotidienne suggérée).
- Durée de conservation légale : la comptabilité belge se conserve 7 ans ; `KEEP_DAYS=30` ne suffit pas pour les archives. Prévoir une sauvegarde annuelle conservée séparément (par exemple après chaque clôture d'exercice).

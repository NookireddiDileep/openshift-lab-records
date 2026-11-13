#!/usr/bin/env bash
# OCP-013: copy data from Pods to the local machine – files, directories, and a verified database backup
set -euo pipefail
OUT=~/pod-copies; mkdir -p "$OUT/web-backup"; cd "$OUT"
W=$(oc get pod -l deployment=app-04 -o jsonpath='{.items[0].metadata.name}')
D=$(oc get pod -l name=mysql-tpl     -o jsonpath='{.items[0].metadata.name}')

# 1) single file (oc cp uses tar inside the container) + integrity check
oc cp "$W:/var/www/html/index.html" ./index.html
diff <(oc exec "$W" -- sha256sum /var/www/html/index.html | cut -d' ' -f1) <(sha256sum index.html | cut -d' ' -f1) && echo "checksum OK"

# 2) directory (destination must exist; uses rsync if the image has it, else tar)
oc rsync "$W:/var/www/html" ./web-backup

# 3) logical database backup – consistent, restorable (credentials stay inside the Pod)
oc exec "$D" -- bash -c 'mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 --no-tablespaces --single-transaction "$MYSQL_DATABASE" 2>/dev/null' > appdb-backup.sql
grep -q "Dump completed" appdb-backup.sql && echo "dump complete"

# 4) restore drill (DESTRUCTIVE – lab only): drop, restore from the local file, verify
# oc exec "$D" -- bash -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 "$MYSQL_DATABASE" -e "DROP TABLE t;"'
# oc exec -i "$D" -- bash -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 "$MYSQL_DATABASE"' < appdb-backup.sql
# oc exec "$D" -- bash -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 "$MYSQL_DATABASE" -e "SELECT * FROM t;"'

#!/usr/bin/env bash
# OCP-012: MySQL from the mysql-persistent OpenShift Template + durability test
set -euo pipefail
oc get templates -n openshift | grep -Ei "mysql|mariadb|postgres"
oc process --parameters mysql-persistent -n openshift
oc get sc

# NOTE: oc new-app prints generated credentials to stdout – don't run this in CI logs as-is
oc new-app --template=mysql-persistent \
  -p DATABASE_SERVICE_NAME=mysql-tpl -p MYSQL_DATABASE=appdb -p VOLUME_CAPACITY=1Gi >/dev/null
oc get pvc mysql-tpl
oc rollout status dc/mysql-tpl --timeout=180s     # template uses a (deprecated) DeploymentConfig

sql() { oc exec "$1" -- bash -c "mysql -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" -h127.0.0.1 \"\$MYSQL_DATABASE\" -e \"$2\" 2>/dev/null"; }
P=$(oc get pod -l name=mysql-tpl -o jsonpath='{.items[0].metadata.name}')
sql "$P" "CREATE TABLE IF NOT EXISTS t(id INT PRIMARY KEY, note VARCHAR(50)); INSERT IGNORE INTO t VALUES (1,'survives a restart?'); SELECT * FROM t;"

# durability test: delete the Pod, read the data back from the replacement
oc delete pod "$P"
sleep 60
N=$(oc get pod -l name=mysql-tpl -o jsonpath='{.items[0].metadata.name}')
sql "$N" "SELECT * FROM t;"

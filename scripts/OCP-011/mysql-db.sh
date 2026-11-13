#!/usr/bin/env bash
# OCP-011: MySQL from a Docker Hub image on OpenShift, credentials from a Secret (never printed)
set -euo pipefail
podman search docker.io/mysql --filter is-official=true

oc create deployment mysql-db --image=docker.io/library/mysql:8.0      # fails until credentials are set

oc create secret generic mysql-db-secret \
  --from-literal=MYSQL_ROOT_PASSWORD="$(openssl rand -base64 12)" \
  --from-literal=MYSQL_USER=appuser \
  --from-literal=MYSQL_PASSWORD="$(openssl rand -base64 12)" \
  --from-literal=MYSQL_DATABASE=appdb
oc set env deployment/mysql-db --from=secret/mysql-db-secret
oc rollout status deployment/mysql-db --timeout=120s

# real readiness check: an SQL query, credentials read from the pod's own environment
oc exec deploy/mysql-db -- bash -c \
  'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 "$MYSQL_DATABASE" -e "SELECT VERSION(), DATABASE(), CURRENT_USER();" 2>/dev/null'

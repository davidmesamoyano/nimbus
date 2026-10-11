#!/usr/bin/env bash
# Crea dos clústeres de Kubernetes (k3d = k3s dentro de Docker):
#   nimbus-dev  → entorno de desarrollo; aquí vive también Argo CD
#   nimbus-prod → entorno de producción
# Ambos comparten la red Docker "nimbus-net" para que Argo CD (en dev)
# pueda gestionar prod: es la versión de bolsillo de un escenario multi-cloud.
source "$(dirname "$0")/lib.sh"

crear() {
  local nombre=$1 puerto=$2
  if cluster_existe "$nombre"; then
    ok "El clúster $nombre ya existe"
    return
  fi
  paso "Creando clúster $nombre (http://*.localhost:$puerto)"
  k3d cluster create "$nombre" \
    --network "$NETWORK" \
    --servers 1 --agents 0 \
    --port "${puerto}:80@loadbalancer" \
    --wait
  ok "Clúster $nombre creado"
}

crear "$DEV_CLUSTER" "$DEV_PORT"
crear "$PROD_CLUSTER" "$PROD_PORT"

kubectl config use-context "$DEV_CTX" >/dev/null
paso "Clústeres listos"
k3d cluster list
echo
echo "Siguiente paso: ./scripts/02-instalar-plataforma.sh"

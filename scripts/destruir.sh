#!/usr/bin/env bash
# Borra los dos clústeres y la red Docker. Tu código y Git no se tocan.
source "$(dirname "$0")/lib.sh"

paso "Borrando clústeres de Nimbus"
for c in "$DEV_CLUSTER" "$PROD_CLUSTER"; do
  if cluster_existe "$c"; then
    k3d cluster delete "$c"
    ok "$c borrado"
  fi
done
docker network rm "$NETWORK" >/dev/null 2>&1 && ok "Red $NETWORK borrada" || true
echo
echo "Para volver a empezar: ./scripts/01-crear-clusters.sh"

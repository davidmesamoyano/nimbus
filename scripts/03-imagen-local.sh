#!/usr/bin/env bash
# Construye la imagen de la app de ejemplo en tu PC y la carga en ambos
# clústeres con la etiqueta "local". Sirve para arrancar sin depender de
# GitHub Actions. Cuando el CI publique imágenes en GHCR, ya no hace falta.
source "$(dirname "$0")/lib.sh"

paso "Construyendo ${IMAGE}:local"
docker build -t "${IMAGE}:local" demo-app
ok "Imagen construida"

paso "Cargando la imagen en los clústeres"
k3d image import "${IMAGE}:local" -c "$DEV_CLUSTER" -c "$PROD_CLUSTER"
ok "Imagen disponible en nimbus-dev y nimbus-prod"

echo
echo "Argo CD desplegará las apps en cuanto lea el repositorio (≈ 1-3 min)."
echo "Comprueba el estado con: kubectl --context ${DEV_CTX} -n apps get pods"

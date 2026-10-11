#!/usr/bin/env bash
# Promociona a producción la versión que está en dev, al estilo GitOps:
# no toca el clúster, cambia Git. Copia la etiqueta de imagen de dev a prod
# en el app.yaml; al hacer commit y push, Argo CD actualiza prod.
#   ./scripts/promover.sh web     → solo web
#   ./scripts/promover.sh         → todas las apps
source "$(dirname "$0")/lib.sh"

promover() {
  local fichero="apps/$1/app.yaml"
  [ -f "$fichero" ] || error "No existe $fichero"
  local tag_dev tag_prod
  tag_dev=$(grep '# nimbus:dev-tag' "$fichero" | sed -E 's/.*tag: *([^ ]+).*/\1/')
  tag_prod=$(grep '# nimbus:prod-tag' "$fichero" | sed -E 's/.*tag: *([^ ]+).*/\1/')
  if [ "$tag_dev" = "$tag_prod" ]; then
    ok "$1: prod ya está en $tag_dev"
    return
  fi
  sed -i -E "s/(tag: *)[^ ]+( *# nimbus:prod-tag)/\1${tag_dev}\2/" "$fichero"
  ok "$1: prod $tag_prod → $tag_dev"
}

if [ -n "${1:-}" ]; then
  promover "$1"
else
  for dir in apps/*/; do promover "$(basename "$dir")"; done
fi

echo
git --no-pager diff --stat -- apps/
echo
echo "Revisa el cambio y publícalo (idealmente con una Pull Request):"
echo "  git commit -am \"release: promover a prod\" && git push"

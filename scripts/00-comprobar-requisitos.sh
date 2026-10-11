#!/usr/bin/env bash
# Comprueba que tienes todas las herramientas necesarias (todas gratuitas).
source "$(dirname "$0")/lib.sh"

paso "Comprobando herramientas"
faltan=0
for cmd in docker k3d kubectl helm git openssl curl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd"
  else
    aviso "Falta: $cmd"
    faltan=1
  fi
done

if [ "$faltan" -eq 1 ]; then
  cat <<'EOF'

En Windows (PowerShell) puedes instalar lo que falte con:
  winget install Docker.DockerDesktop
  winget install k3d.k3d
  winget install Kubernetes.kubectl
  winget install Helm.Helm
  winget install Git.Git        # incluye Git Bash, openssl y curl
Después cierra y vuelve a abrir la terminal.
EOF
  exit 1
fi

paso "Comprobando que Docker está arrancado"
docker info >/dev/null 2>&1 || error "Docker no responde. Abre Docker Desktop y espera a que arranque."
ok "Docker funciona"

mem_gb=$(docker info --format '{{.MemTotal}}' | awk '{printf "%d", $1/1024/1024/1024}')
if [ "${mem_gb:-0}" -lt 6 ]; then
  aviso "Docker tiene ${mem_gb} GB de RAM. Se recomiendan 6 GB o más (Docker Desktop → Settings → Resources)."
else
  ok "Docker tiene ${mem_gb} GB de RAM"
fi

paso "Todo listo. Siguiente paso: ./scripts/01-crear-clusters.sh"

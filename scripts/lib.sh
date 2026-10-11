#!/usr/bin/env bash
# Funciones y variables comunes a todos los scripts de Nimbus.
# Pensado para Git Bash en Windows, Linux y macOS.

# shellcheck disable=SC2034  # variables usadas por los scripts que cargan este fichero
set -euo pipefail

# En Git Bash (Windows) evita que rutas como "/CN=..." se conviertan en
# rutas de Windows al pasarlas a openssl, docker, etc.
export MSYS_NO_PATHCONV=1

# Ir siempre a la raíz del repositorio
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd)"

NETWORK="nimbus-net"
DEV_CLUSTER="nimbus-dev"
PROD_CLUSTER="nimbus-prod"
DEV_CTX="k3d-${DEV_CLUSTER}"
PROD_CTX="k3d-${PROD_CLUSTER}"
DEV_PORT=9080     # http://web.localhost:9080  → entorno dev
PROD_PORT=9090    # http://web.localhost:9090  → entorno prod
IMAGE="ghcr.io/davidmesamoyano/nimbus-demo-app"
STATE_DIR="${ROOT}/.nimbus"   # certificados y ficheros locales (no se suben a Git)

paso()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
error() { printf '\033[1;31m  ✘ %s\033[0m\n' "$*" >&2; exit 1; }

cluster_existe() { k3d cluster list "$1" >/dev/null 2>&1; }

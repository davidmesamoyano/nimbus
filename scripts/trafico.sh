#!/usr/bin/env bash
# Genera tráfico contra web para ver datos en Grafana (Ctrl+C para parar).
# Aproximadamente 1 de cada 10 peticiones fuerza un error 500.
#   ./scripts/trafico.sh        → dev
#   ./scripts/trafico.sh prod   → prod
source "$(dirname "$0")/lib.sh"

PORT=$DEV_PORT
[ "${1:-}" = "prod" ] && PORT=$PROD_PORT
URL="http://web.localhost:${PORT}/"

paso "Enviando tráfico a ${URL} (Ctrl+C para parar)"
n=0
while true; do
  n=$((n + 1))
  if [ $((RANDOM % 10)) -eq 0 ]; then
    curl -s -o /dev/null -m 3 "${URL}?fail=1" || true
  else
    curl -s -o /dev/null -m 3 "$URL" || true
  fi
  [ $((n % 50)) -eq 0 ] && echo "  ${n} peticiones enviadas"
  sleep 0.2
done

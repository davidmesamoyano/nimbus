#!/usr/bin/env bash
# Demostración en 3 pasos de la seguridad de la plataforma (ideal para el
# GIF del README o para enseñarlo en una entrevista):
#   1. web → api funciona (está declarado en el talksTo de web)
#   2. un pod "intruso" NO puede llegar a api (zero trust)
#   3. el tráfico entre web y api va cifrado con mTLS (Linkerd)
source "$(dirname "$0")/lib.sh"

CTX="${1:-$DEV_CTX}"
PORT=$DEV_PORT
[ "$CTX" = "$PROD_CTX" ] && PORT=$PROD_PORT

paso "1/3  Petición a web (que llama a api) desde fuera del clúster"
respuesta=$(curl -s -m 5 "http://web.localhost:${PORT}/") || true
echo "  $respuesta"
if echo "$respuesta" | grep -q '"ok": true'; then
  ok "web → api permitido (api está en el talksTo de web)"
else
  aviso "No hubo respuesta correcta. ¿Están los pods listos? kubectl --context $CTX -n apps get pods"
fi

paso "2/3  Un pod intruso (namespace default) intenta llamar a api"
if kubectl --context "$CTX" run intruso --rm -i --quiet --restart=Never \
     --image=curlimages/curl:8.10.1 -- \
     curl -s -m 5 -o /dev/null -w '%{http_code}' http://api.apps.svc.cluster.local/ 2>/dev/null; then
  echo
  aviso "El intruso ha llegado a api: revisa las NetworkPolicies"
else
  echo
  ok "Conexión bloqueada: api no acepta tráfico de quien no la declara en talksTo"
fi

paso "3/3  Comprobando que web ↔ api va cifrado con mTLS"
for _ in 1 2 3 4 5; do curl -s -m 3 "http://web.localhost:${PORT}/" >/dev/null || true; done
pod=$(kubectl --context "$CTX" -n apps get pod -l nimbus.io/app=web -o jsonpath='{.items[0].metadata.name}')
kubectl --context "$CTX" -n apps port-forward "pod/${pod}" 4191:4191 >/dev/null 2>&1 &
pf=$!
sleep 3
conexiones_tls=$(curl -s http://localhost:4191/metrics | grep -c 'tls="true"' || true)
kill "$pf" 2>/dev/null || true
if [ "${conexiones_tls:-0}" -gt 0 ]; then
  ok "El proxy de Linkerd de web reporta ${conexiones_tls} métricas de conexiones con tls=\"true\""
else
  aviso "No se encontraron conexiones mTLS. ¿Tiene el pod 2 contenedores (app + linkerd-proxy)?"
fi

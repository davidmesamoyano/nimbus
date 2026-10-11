#!/usr/bin/env bash
# Abre el acceso a las consolas de la plataforma (Ctrl+C para cerrar).
#   ./scripts/abrir.sh argocd   → https://localhost:8443
#   ./scripts/abrir.sh grafana  → http://localhost:3000
source "$(dirname "$0")/lib.sh"

case "${1:-}" in
  argocd)
    pass=$(kubectl --context "$DEV_CTX" -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d)
    paso "Argo CD → https://localhost:8443  (acepta el aviso del certificado)"
    echo "  Usuario: admin"
    echo "  Contraseña: ${pass}"
    kubectl --context "$DEV_CTX" -n argocd port-forward svc/argocd-server 8443:443
    ;;
  grafana)
    paso "Grafana → http://localhost:3000  (admin / nimbus)"
    echo "  Panel: Dashboards → Nimbus · Apps"
    kubectl --context "$DEV_CTX" -n monitoring port-forward svc/monitoring-grafana 3000:80
    ;;
  *)
    echo "Uso: $0 argocd|grafana"
    exit 1
    ;;
esac

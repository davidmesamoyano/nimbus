#!/usr/bin/env bash
# Instala los componentes de la plataforma:
#   - Linkerd (mTLS entre servicios) en dev y prod
#   - Namespace "apps" con política default-deny en dev y prod
#   - Prometheus + Grafana en dev
#   - Argo CD en dev, gestionando ambos clústeres (GitOps)
source "$(dirname "$0")/lib.sh"

CERTS="${STATE_DIR}/certs"

# ─── 1. Certificados de Linkerd ──────────────────────────────────────
# Linkerd necesita una CA raíz (trust anchor) y un certificado emisor para
# firmar los certificados mTLS de cada pod. La misma raíz en ambos clústeres.
generar_certificados() {
  if [ -f "${CERTS}/issuer.crt" ]; then
    ok "Certificados de Linkerd ya generados"
    return
  fi
  paso "Generando certificados de Linkerd (ECDSA P-256)"
  mkdir -p "$CERTS"
  openssl ecparam -name prime256v1 -genkey -noout -out "${CERTS}/ca.key"
  openssl req -x509 -new -key "${CERTS}/ca.key" -sha256 -days 3650 \
    -subj "/CN=root.linkerd.cluster.local" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "${CERTS}/ca.crt"
  openssl ecparam -name prime256v1 -genkey -noout -out "${CERTS}/issuer.key"
  openssl req -new -key "${CERTS}/issuer.key" \
    -subj "/CN=identity.linkerd.cluster.local" -out "${CERTS}/issuer.csr"
  printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > "${CERTS}/issuer.ext"
  openssl x509 -req -in "${CERTS}/issuer.csr" \
    -CA "${CERTS}/ca.crt" -CAkey "${CERTS}/ca.key" -CAcreateserial \
    -days 365 -sha256 -extfile "${CERTS}/issuer.ext" -out "${CERTS}/issuer.crt"
  ok "Certificados en .nimbus/certs (no se suben a Git)"
}

# ─── 2. Linkerd + namespace apps ─────────────────────────────────────
instalar_linkerd() {
  local ctx=$1
  paso "Instalando Linkerd en $ctx"
  helm upgrade --install linkerd-crds linkerd-edge/linkerd-crds \
    --kube-context "$ctx" -n linkerd --create-namespace --wait
  helm upgrade --install linkerd-control-plane linkerd-edge/linkerd-control-plane \
    --kube-context "$ctx" -n linkerd --wait --timeout 10m \
    --set-file identityTrustAnchorsPEM="${CERTS}/ca.crt" \
    --set-file identity.issuer.tls.crtPEM="${CERTS}/issuer.crt" \
    --set-file identity.issuer.tls.keyPEM="${CERTS}/issuer.key"
  ok "Linkerd listo en $ctx"

  # El namespace se crea antes que las apps para que sus pods nazcan ya
  # con el proxy de Linkerd. Después Argo CD lo mantiene (nimbus-base).
  kubectl --context "$ctx" apply -f platform/namespace/apps.yaml >/dev/null
  ok "Namespace apps (Linkerd + default-deny) en $ctx"
}

# ─── 3. Monitorización (solo dev) ────────────────────────────────────
instalar_monitorizacion() {
  paso "Instalando Prometheus y Grafana en $DEV_CTX (tarda unos minutos)"
  helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --kube-context "$DEV_CTX" -n monitoring --create-namespace --wait --timeout 10m \
    -f platform/monitoring/kube-prometheus-stack-values.yaml
  kubectl --context "$DEV_CTX" apply -f platform/monitoring/grafana-dashboard.yaml >/dev/null
  ok "Prometheus + Grafana listos (con el panel 'Nimbus · Apps')"
}

# ─── 4. Argo CD y registro de clústeres ──────────────────────────────
instalar_argocd() {
  paso "Instalando Argo CD en $DEV_CTX"
  helm upgrade --install argocd argo/argo-cd \
    --kube-context "$DEV_CTX" -n argocd --create-namespace --wait --timeout 10m \
    --set dex.enabled=false --set notifications.enabled=false
  ok "Argo CD instalado"
}

registrar_clusteres() {
  paso "Registrando los clústeres en Argo CD"

  # dev: el propio clúster donde corre Argo CD
  kubectl --context "$DEV_CTX" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-nimbus-dev
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    nimbus.io/environment: dev
stringData:
  name: nimbus-dev
  server: https://kubernetes.default.svc
EOF
  ok "nimbus-dev registrado (entorno dev)"

  # prod: Argo CD lo alcanza por la red Docker compartida, usando la IP
  # del nodo de prod y las credenciales de su kubeconfig
  local ip ca cert key
  ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"${NETWORK}\").IPAddress}}" "k3d-${PROD_CLUSTER}-server-0")
  ca=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${PROD_CTX}\")].cluster.certificate-authority-data}")
  cert=$(kubectl config view --raw -o jsonpath="{.users[?(@.name==\"admin@${PROD_CTX}\")].user.client-certificate-data}")
  key=$(kubectl config view --raw -o jsonpath="{.users[?(@.name==\"admin@${PROD_CTX}\")].user.client-key-data}")
  [ -n "$ip" ] && [ -n "$ca" ] && [ -n "$cert" ] && [ -n "$key" ] \
    || error "No se pudieron leer los datos del clúster prod (¿existe? ejecuta 01-crear-clusters.sh)"

  kubectl --context "$DEV_CTX" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-nimbus-prod
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    nimbus.io/environment: prod
stringData:
  name: nimbus-prod
  server: https://${ip}:6443
  config: |
    {
      "tlsClientConfig": {
        "caData": "${ca}",
        "certData": "${cert}",
        "keyData": "${key}"
      }
    }
EOF
  ok "nimbus-prod registrado (entorno prod, https://${ip}:6443)"
}

aplicar_gitops() {
  paso "Activando GitOps: Argo CD empieza a vigilar el repositorio"
  kubectl --context "$DEV_CTX" apply -f platform/argocd/project.yaml >/dev/null
  kubectl --context "$DEV_CTX" apply -f platform/argocd/applicationsets.yaml >/dev/null
  ok "ApplicationSets nimbus-apps y nimbus-base creados"
}

# ─── Ejecución ───────────────────────────────────────────────────────
cluster_existe "$DEV_CLUSTER" && cluster_existe "$PROD_CLUSTER" \
  || error "Faltan clústeres. Ejecuta primero ./scripts/01-crear-clusters.sh"

paso "Añadiendo repositorios de Helm"
helm repo add linkerd-edge https://helm.linkerd.io/edge >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
ok "Repositorios actualizados"

generar_certificados
instalar_linkerd "$DEV_CTX"
instalar_linkerd "$PROD_CTX"
instalar_monitorizacion
instalar_argocd
registrar_clusteres
aplicar_gitops

paso "Plataforma instalada"
cat <<EOF
  Argo CD:  ./scripts/abrir.sh argocd    → https://localhost:8443
  Grafana:  ./scripts/abrir.sh grafana   → http://localhost:3000  (admin / nimbus)

Si aún no has subido imágenes con GitHub Actions, carga la imagen local:
  ./scripts/03-imagen-local.sh
EOF

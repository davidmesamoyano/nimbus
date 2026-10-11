"""
Nimbus demo app.

Microservicio mínimo (solo librería estándar de Python) que sirve para
probar la plataforma. La misma imagen se usa para varias "apps" del catálogo
(web, api...), cambiando su comportamiento con variables de entorno:

  APP_NAME       nombre de la app (lo inyecta la plataforma)
  NIMBUS_ENV     entorno: dev / prod (lo inyecta la plataforma)
  MESSAGE        texto que devuelve en "/"
  UPSTREAM_URL   si se define, "/" llama a esa URL y devuelve su respuesta
                 (así web -> api demuestra la comunicación entre servicios)
  PORT           puerto de escucha (por defecto 8080)

Endpoints:
  /         respuesta JSON (y llamada al upstream si existe)
  /healthz  comprobación de salud para Kubernetes
  /metrics  métricas en formato Prometheus
  /?fail=1  fuerza un error 500 (útil para ver la tasa de errores en Grafana)
"""

import json
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

APP_NAME = os.environ.get("APP_NAME", "demo")
ENVIRONMENT = os.environ.get("NIMBUS_ENV", "local")
MESSAGE = os.environ.get("MESSAGE", "Hola desde Nimbus")
UPSTREAM_URL = os.environ.get("UPSTREAM_URL", "")
PORT = int(os.environ.get("PORT", "8080"))

# Límites de los "buckets" del histograma de latencia (segundos)
BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5)


class Metrics:
    """Contadores e histograma en memoria, expuestos en formato Prometheus."""

    def __init__(self):
        self._lock = threading.Lock()
        self.requests = {}  # (path, code) -> contador
        self.bucket_counts = [0] * len(BUCKETS)
        self.duration_sum = 0.0
        self.duration_count = 0

    def observe(self, path, code, seconds):
        with self._lock:
            key = (path, str(code))
            self.requests[key] = self.requests.get(key, 0) + 1
            for i, limit in enumerate(BUCKETS):
                if seconds <= limit:
                    self.bucket_counts[i] += 1
            self.duration_sum += seconds
            self.duration_count += 1

    def render(self):
        with self._lock:
            lines = [
                "# HELP nimbus_http_requests_total Peticiones HTTP atendidas.",
                "# TYPE nimbus_http_requests_total counter",
            ]
            for (path, code), value in sorted(self.requests.items()):
                lines.append(
                    f'nimbus_http_requests_total{{app="{APP_NAME}",path="{path}",code="{code}"}} {value}'
                )
            lines += [
                "# HELP nimbus_http_request_duration_seconds Latencia de las peticiones.",
                "# TYPE nimbus_http_request_duration_seconds histogram",
            ]
            # Los buckets de Prometheus son acumulados: observe() ya suma en
            # todos los buckets cuyo límite es >= a la duración.
            for limit, value in zip(BUCKETS, self.bucket_counts):
                lines.append(
                    f'nimbus_http_request_duration_seconds_bucket{{app="{APP_NAME}",le="{limit}"}} {value}'
                )
            lines.append(
                f'nimbus_http_request_duration_seconds_bucket{{app="{APP_NAME}",le="+Inf"}} {self.duration_count}'
            )
            lines.append(f'nimbus_http_request_duration_seconds_sum{{app="{APP_NAME}"}} {self.duration_sum:.6f}')
            lines.append(f'nimbus_http_request_duration_seconds_count{{app="{APP_NAME}"}} {self.duration_count}')
            return "\n".join(lines) + "\n"


METRICS = Metrics()


def call_upstream():
    """Llama al servicio configurado en UPSTREAM_URL y devuelve su JSON."""
    try:
        with urllib.request.urlopen(UPSTREAM_URL, timeout=2) as resp:
            return {"ok": True, "status": resp.status, "body": json.loads(resp.read())}
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        return {"ok": False, "error": str(exc)}


class Handler(BaseHTTPRequestHandler):
    server_version = "nimbus-demo/1.0"

    def _send(self, code, body, content_type="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        start = time.perf_counter()
        url = urlparse(self.path)
        code = 200

        if url.path == "/healthz":
            self._send(200, '{"status":"ok"}')
            return  # no contamos las sondas de salud en las métricas
        if url.path == "/metrics":
            self._send(200, METRICS.render(), "text/plain; version=0.0.4")
            return

        if url.path == "/":
            if parse_qs(url.query).get("fail") == ["1"]:
                code = 500
                body = {"app": APP_NAME, "error": "fallo provocado (?fail=1)"}
            else:
                body = {"app": APP_NAME, "env": ENVIRONMENT, "message": MESSAGE}
                if UPSTREAM_URL:
                    body["upstream"] = call_upstream()
                    if not body["upstream"]["ok"]:
                        code = 502
        else:
            code = 404
            body = {"error": "not found"}

        self._send(code, json.dumps(body, ensure_ascii=False))
        METRICS.observe(url.path if code != 404 else "other", code, time.perf_counter() - start)

    def log_message(self, fmt, *args):
        # Log en una línea, en stdout, como se espera en contenedores
        print(f"{APP_NAME} {self.address_string()} {fmt % args}", flush=True)


def make_server(port=PORT):
    return ThreadingHTTPServer(("0.0.0.0", port), Handler)


if __name__ == "__main__":
    print(f"{APP_NAME} ({ENVIRONMENT}) escuchando en :{PORT}", flush=True)
    make_server().serve_forever()

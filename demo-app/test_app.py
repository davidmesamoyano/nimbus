"""Tests de la app de ejemplo: python -m unittest -v (desde demo-app/)."""

import json
import os
import threading
import unittest
import urllib.error
import urllib.request

import app


def get(port, path):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=3) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


class DemoAppTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Dos instancias: "api" y "web" (que llama a api), como en el clúster
        cls.api = app.make_server(0)
        cls.api_port = cls.api.server_address[1]
        threading.Thread(target=cls.api.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.api.shutdown()

    def test_healthz(self):
        code, body = get(self.api_port, "/healthz")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)["status"], "ok")

    def test_root_returns_message(self):
        code, body = get(self.api_port, "/")
        self.assertEqual(code, 200)
        self.assertIn("message", json.loads(body))

    def test_forced_failure(self):
        code, _ = get(self.api_port, "/?fail=1")
        self.assertEqual(code, 500)

    def test_unknown_path(self):
        code, _ = get(self.api_port, "/nada")
        self.assertEqual(code, 404)

    def test_metrics_count_requests(self):
        get(self.api_port, "/")
        code, body = get(self.api_port, "/metrics")
        self.assertEqual(code, 200)
        self.assertIn("nimbus_http_requests_total", body)
        self.assertIn('code="200"', body)
        self.assertIn('le="+Inf"', body)

    def test_upstream_ok_and_down(self):
        # Llamada correcta al upstream (a /healthz para no llamarse en bucle)
        app.UPSTREAM_URL = f"http://127.0.0.1:{self.api_port}/healthz"
        try:
            code, body = get(self.api_port, "/")
            self.assertEqual(code, 200)
            self.assertTrue(json.loads(body)["upstream"]["ok"])
            # Upstream caído (o bloqueado por la red) -> 502
            app.UPSTREAM_URL = "http://127.0.0.1:1/"
            code, body = get(self.api_port, "/")
            self.assertEqual(code, 502)
            self.assertFalse(json.loads(body)["upstream"]["ok"])
        finally:
            app.UPSTREAM_URL = ""


if __name__ == "__main__":
    unittest.main()

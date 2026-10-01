import os
import time
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import redis
import psycopg2
from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("micro-api")

PORT = int(os.getenv("PORT", "8000"))
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")
POSTGRES_USER = os.getenv("POSTGRES_USER", "appuser")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "appsecret")
POSTGRES_DB = os.getenv("POSTGRES_DB", "appdb")

# Prometheus Metrics definition
REQUESTS_TOTAL = Counter("nested_api_requests_total", "Total requests received by nested microservice", ["path", "status"])
REDIS_CONNECTED = Gauge("nested_cache_connected", "Redis connection status (1 = connected, 0 = disconnected)")
POSTGRES_CONNECTED = Gauge("nested_db_connected", "Postgres connection status (1 = connected, 0 = disconnected)")
START_TIME = time.time()

def check_redis():
    try:
        r = redis.Redis(host=REDIS_HOST, port=6379, socket_timeout=2)
        r.ping()
        val = r.incr("request_counter")
        REDIS_CONNECTED.set(1)
        return True, int(val)
    except Exception as e:
        logger.warning(f"Redis check failed: {e}")
        REDIS_CONNECTED.set(0)
        return False, 0

def check_postgres():
    try:
        conn = psycopg2.connect(
            host=POSTGRES_HOST,
            user=POSTGRES_USER,
            password=POSTGRES_PASSWORD,
            dbname=POSTGRES_DB,
            connect_timeout=2
        )
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.close()
        conn.close()
        POSTGRES_CONNECTED.set(1)
        return True
    except Exception as e:
        logger.warning(f"Postgres check failed: {e}")
        POSTGRES_CONNECTED.set(0)
        return False

class MicroApiHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/health"):
            redis_ok, counter = check_redis()
            pg_ok = check_postgres()
            REQUESTS_TOTAL.labels(path=self.path, status="200").inc()
            
            payload = {
                "service": "nested-micro-api",
                "orchestrator": "Docker-in-Docker (DinD)",
                "cluster": "cluster-3",
                "status": "healthy",
                "uptime_seconds": round(time.time() - START_TIME, 2),
                "dependencies": {
                    "redis": {"connected": redis_ok, "requests_cached": counter},
                    "postgres": {"connected": pg_ok}
                }
            }
            body = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        elif self.path == "/metrics":
            # Refresh dependency states before Prometheus scrape
            check_redis()
            check_postgres()
            data = generate_latest()
            REQUESTS_TOTAL.labels(path="/metrics", status="200").inc()
            
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            
        else:
            REQUESTS_TOTAL.labels(path=self.path, status="404").inc()
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error": "not found"}')

    def log_message(self, format, *args):
        # Mute repetitive scrape logs
        return

if __name__ == "__main__":
    logger.info(f"Starting Nested Micro API on port {PORT}...")
    server = HTTPServer(("0.0.0.0", PORT), MicroApiHandler)
    server.serve_forever()

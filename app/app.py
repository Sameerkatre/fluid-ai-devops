import os
import time
import logging
from flask import Flask, jsonify
import redis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST", "redis-service")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
APP_VERSION = os.environ.get("APP_VERSION", "1.0.0")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True, socket_connect_timeout=2)


@app.route("/")
def index():
    log.info("Root endpoint hit")
    return jsonify({
        "service": "fluid-ai-demo",
        "version": APP_VERSION,
        "status": "ok"
    })


@app.route("/health")
def health():
    # Liveness probe — just checks if process is alive
    return jsonify({"status": "alive"}), 200


@app.route("/ready")
def ready():
    # Readiness probe — checks if Redis is reachable
    try:
        r = get_redis()
        r.ping()
        log.info("Readiness check passed")
        return jsonify({"status": "ready", "redis": "connected"}), 200
    except Exception as e:
        log.error(f"Readiness check failed: {e}")
        return jsonify({"status": "not ready", "redis": "unreachable", "error": str(e)}), 503


@app.route("/count")
def count():
    try:
        r = get_redis()
        visits = r.incr("visits")
        log.info(f"Visit count: {visits}")
        return jsonify({"visits": visits, "message": "Counter incremented"})
    except Exception as e:
        log.error(f"Count failed: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/info")
def info():
    return jsonify({
        "redis_host": REDIS_HOST,
        "redis_port": REDIS_PORT,
        "version": APP_VERSION,
        "pod": os.environ.get("HOSTNAME", "unknown")
    })


if __name__ == "__main__":
    log.info(f"Starting app v{APP_VERSION} — Redis at {REDIS_HOST}:{REDIS_PORT}")
    app.run(host="0.0.0.0", port=5000)

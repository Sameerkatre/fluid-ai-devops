import os
import redis
from flask import Flask, jsonify

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST", "redis-service")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

@app.route("/")
def index():
    return jsonify({"service": "fluid-ai-demo", "status": "ok"})

@app.route("/health")
def health():
    return jsonify({"status": "alive"})

@app.route("/ready")
def ready():
    try:
        r = get_redis()
        r.ping()
        return jsonify({"status": "ready", "redis": "connected"})
    except Exception as e:
        return jsonify({"status": "not ready", "redis": str(e)}), 503

@app.route("/count")
def count():
    try:
        r = get_redis()
        visits = r.incr("visits")
        return jsonify({"visits": visits, "message": "Counter incremented"})
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route("/info")
def info():
    return jsonify({
        "redis_host": REDIS_HOST,
        "redis_port": REDIS_PORT,
        "pod_name": os.environ.get("HOSTNAME", "unknown"),
        "version": os.environ.get("APP_VERSION", "1.0.0")
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
# pipeline trigger Sun 24 May 2026 21:12:57 IST
# pipeline trigger Sun 24 May 2026 21:50:30 IST
# pipeline trigger Sun 24 May 2026 22:03:51 IST
# pipeline trigger Sun 24 May 2026 22:43:20 IST
# pipeline trigger Mon 25 May 2026 08:31:52 IST
# pipeline trigger Mon 25 May 2026 09:08:30 IST

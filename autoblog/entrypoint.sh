#!/bin/bash
set -euo pipefail

echo "[autoblog] bootstrap starting…"
/opt/autoblog/bin/bootstrap-volumes.sh
echo "[autoblog] bootstrap complete"

echo "[autoblog] starting astro dev on :4321"
touch /var/log/astro-dev.log
chown autoblog:autoblog /var/log/astro-dev.log
start-stop-daemon --start --background --chuid autoblog:autoblog \
  --chdir /site/dev \
  --make-pidfile --pidfile /var/run/astro-dev.pid \
  --startas /bin/bash -- \
  -c "exec npm run dev -- --host 0.0.0.0 --port 4321 >> /var/log/astro-dev.log 2>&1"

echo "[autoblog] starting ingest-loop"
touch /var/log/ingest-loop.log
chown autoblog:autoblog /var/log/ingest-loop.log
start-stop-daemon --start --background --chuid autoblog:autoblog \
  --chdir /agent \
  --make-pidfile --pidfile /var/run/ingest-loop.pid \
  --startas /bin/bash -- \
  -c "export ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY:-}' \
             INGEST_ENABLED='${INGEST_ENABLED:-1}' \
             INGEST_POLL_INTERVAL='${INGEST_POLL_INTERVAL:-300}' \
             INGEST_STABILITY_SECS='${INGEST_STABILITY_SECS:-60}' \
             INGEST_BATCH_BYTES='${INGEST_BATCH_BYTES:-200000}' \
             INGEST_MAX_BATCHES_PER_WAKE='${INGEST_MAX_BATCHES_PER_WAKE:-50}'; \
          exec /opt/autoblog/bin/ingest-loop.sh >> /var/log/ingest-loop.log 2>&1"

echo "[autoblog] starting sshd"
exec /usr/sbin/sshd -D -e

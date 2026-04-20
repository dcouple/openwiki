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

echo "[autoblog] starting sshd"
exec /usr/sbin/sshd -D -e

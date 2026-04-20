#!/bin/bash
set -euo pipefail

echo "[autoblog] bootstrap starting…"
/opt/autoblog/bin/bootstrap-volumes.sh
echo "[autoblog] bootstrap complete; starting sshd."

exec /usr/sbin/sshd -D -e

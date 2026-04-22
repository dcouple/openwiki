FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server tmux git curl ca-certificates sudo \
    python3 build-essential jq tini rsync \
    && rm -rf /var/lib/apt/lists/*

# Node 20 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# User
RUN useradd --create-home --shell /bin/bash --uid 1000 autoblog \
    && usermod -aG sudo autoblog \
    && echo 'autoblog ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/autoblog

# tmux auto-attach on SSH login
RUN echo 'if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then exec tmux new-session -A -s main -c /agent; fi' \
    >> /home/autoblog/.bashrc \
    && chown autoblog:autoblog /home/autoblog/.bashrc

# sshd config + entrypoint scripts
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh bootstrap-volumes.sh /opt/autoblog/bin/
RUN chmod +x /opt/autoblog/bin/*.sh

# Templates (read at first boot; never mutated at runtime)
COPY templates/ /opt/autoblog/templates/

# Pre-install node_modules (dev only — prod serves pre-built dist, doesn't need
# them) and pre-build the prod dist inside the image. `mv` (not cp) so the seed
# template doesn't also carry node_modules/dist. bootstrap-volumes.sh copies
# these into /site/dev/node_modules and /site/prod/dist after worktree creation.
RUN cd /opt/autoblog/templates/site-template \
    && npm ci \
    && npm run build \
    && mv node_modules /opt/autoblog/templates/site-template-node_modules \
    && mv dist         /opt/autoblog/templates/site-template-dist

# Host-side artifacts the installer extracts from the image at install time.
COPY host-files/compose.yml          /opt/openwiki/compose.yml
COPY host-files/Caddyfile.template   /opt/openwiki/Caddyfile.template
COPY host-files/openwiki             /opt/openwiki/openwiki
RUN chmod +x /opt/openwiki/openwiki

RUN mkdir -p /var/run/sshd /agent /site

EXPOSE 22 4321
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/autoblog/bin/entrypoint.sh"]

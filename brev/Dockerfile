# OpenClaw runtime only. The model runs in a separate NVIDIA vLLM container.
FROM node:24-bookworm-slim

ARG OPENCLAW_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        procps \
        ripgrep \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
    && openclaw --version

ENV HOME=/root \
    TERM=xterm-256color

RUN mkdir -p /root/.openclaw/workspace

WORKDIR /root

EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]

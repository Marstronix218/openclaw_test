# OpenClaw runtime only. The model runs in a separate NVIDIA vLLM container.
FROM node:24-bookworm-slim

ARG OPENCLAW_VERSION=2026.6.1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        procps \
        python3 \
        python3-pip \
        ripgrep \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
    && openclaw --version

RUN python3 -m pip install --no-cache-dir --break-system-packages \
        "fastapi>=0.115.0" \
        "openai>=1.60.0" \
        "uvicorn[standard]>=0.30.0" \
        "weave>=0.51.0"

COPY weave_proxy.py /opt/openclaw/weave_proxy.py

ENV HOME=/root \
    TERM=xterm-256color

RUN mkdir -p /root/.openclaw/workspace

WORKDIR /root

EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]

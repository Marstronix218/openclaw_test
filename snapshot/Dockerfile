# OpenClaw gateway + Hugging Face Inference Providers proxy (Weave-traced).
# Base: Node 24 (OpenClaw recommends Node 24, requires >=22).
FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        ripgrep \
        jq \
        python3 \
        python3-pip \
        openssh-client \
        procps \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest \
    && openclaw --version

# HF InferenceClient proxy (no local torch/transformers — inference runs on the provider).
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        "huggingface_hub>=0.28.0" \
        "fastapi>=0.115.0" "uvicorn[standard]>=0.30.0" \
        "weave>=0.51.0"

ENV HOME=/root \
    TERM=xterm-256color
RUN mkdir -p /root/.openclaw/workspace

WORKDIR /root

EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]

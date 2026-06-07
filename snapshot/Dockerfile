# Maxed-out Daytona snapshot for running OpenClaw entirely inside the sandbox.
# Base: Node 24 (OpenClaw recommends Node 24, requires >=22).
FROM node:24-bookworm-slim

# Tooling OpenClaw and its skills commonly rely on at runtime.
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

# Pre-bake OpenClaw so the sandbox boots ready-to-run (no cold install).
RUN npm install -g openclaw@latest \
    && openclaw --version

# --- Local model serving (Qwen2.5-1.5B-Instruct) -------------------------
# download.pytorch.org is NOT reachable from inside Daytona sandboxes, so the
# CPU build of torch + the model weights are baked in here at build time
# (this image is built locally where the network is unrestricted).
ARG MODEL_ID=Qwen/Qwen2.5-1.5B-Instruct
ENV HF_HOME=/root/.cache/huggingface \
    MODEL_ID=${MODEL_ID}

# CPU-only torch first (from the cpu wheel index) so transformers does not pull
# the multi-GB CUDA build as a dependency.
# NOTE: torch 2.5.1+cpu lacks float8_e8m0fnu, which transformers 5.x requires at
# import time. Pin a transformers 4.x stack (and matching tokenizers/hub) that
# works with this torch and supports Qwen2.5.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        torch --index-url https://download.pytorch.org/whl/cpu \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        "transformers==4.46.3" "tokenizers==0.20.3" "huggingface_hub==0.26.2" \
        "accelerate==1.1.1" "safetensors==0.4.5" \
        "fastapi>=0.115.0" "uvicorn[standard]>=0.30.0" \
        "weave>=0.51.0"

# Pre-download the model weights into the HF cache.
RUN python3 -c "from huggingface_hub import snapshot_download; snapshot_download('${MODEL_ID}')"

# OpenClaw derives its home from HOME ($HOME/.openclaw). Do NOT set OPENCLAW_HOME
# to that same path or it nests as ~/.openclaw/.openclaw.
ENV HOME=/root \
    TERM=xterm-256color
RUN mkdir -p /root/.openclaw/workspace

WORKDIR /root

# Gateway control UI / API port.
EXPOSE 18789

# Keep the sandbox alive; we drive onboarding + the gateway via `daytona exec`.
# tini reaps zombies from the long-running gateway + browser subprocesses.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]

# OpenClaw + local Qwen model server (CPU torch + weights baked at build time).
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

# --- Local model serving (Qwen2.5-1.5B-Instruct) -------------------------
ARG MODEL_ID=Qwen/Qwen2.5-1.5B-Instruct
ENV HF_HOME=/root/.cache/huggingface \
    MODEL_ID=${MODEL_ID}

# CPU-only torch (from the cpu wheel index) so transformers does not pull CUDA.
# torch 2.5.1+cpu lacks float8_e8m0fnu, which transformers 5.x requires at import
# time. Pin a transformers 4.x stack that works with this torch and Qwen2.5.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        torch --index-url https://download.pytorch.org/whl/cpu \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        "transformers==4.46.3" "tokenizers==0.20.3" "huggingface_hub==0.26.2" \
        "accelerate==1.1.1" "safetensors==0.4.5" \
        "fastapi>=0.115.0" "uvicorn[standard]>=0.30.0" \
        "weave>=0.51.0"

RUN python3 -c "from huggingface_hub import snapshot_download; snapshot_download('${MODEL_ID}')"

ENV HOME=/root \
    TERM=xterm-256color

RUN mkdir -p /root/.openclaw/workspace

WORKDIR /root

EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]

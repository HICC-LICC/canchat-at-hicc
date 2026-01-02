# syntax=docker/dockerfile:1

# ==== BUILD ARGS ====
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_CUDA_VER=cu121
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""
ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"
ARG BUILD_HASH=dev-build
ARG UID=0
ARG GID=0

######## WebUI frontend ########
FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS build
ARG BUILD_HASH

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ENV APP_BUILD_HASH=${BUILD_HASH}
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN npm run build

######## WebUI backend ########
FROM python:3.11-slim-bookworm AS base

# ==== ARGs and ENVs ====
ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL
ARG UID
ARG GID

ENV ENV=prod \
    PORT=8080 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL} \
    OLLAMA_BASE_URL="/ollama" \
    OPENAI_API_BASE_URL="" \
    OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false \
    WHISPER_MODEL="base" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models" \
    TIKTOKEN_ENCODING_NAME="cl100k_base" \
    TIKTOKEN_CACHE_DIR="/app/backend/data/cache/tiktoken" \
    HF_HOME="/app/backend/data/cache/embedding/models"

WORKDIR /app/backend
ENV HOME=/root

# === Fix apt sources to use HTTPS ===
RUN echo "deb https://deb.debian.org/debian bookworm main\n\
deb https://deb.debian.org/debian-security bookworm-security main\n\
deb https://deb.debian.org/debian bookworm-updates main" > /etc/apt/sources.list

# === Install CA certificates early for pip SSL ===
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

# === User/Group Setup ===
RUN if [ "$UID" -ne 0 ]; then \
      if [ "$GID" -ne 0 ]; then addgroup --gid $GID app; fi; \
      adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma \
    && echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id \
    && chown -R $UID:$GID /app $HOME

# === Install system dependencies ===
ARG USE_OLLAMA=false
RUN set -eux; \
  if [ "$USE_OLLAMA" = "true" ]; then \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      docker.io \
      git build-essential pandoc netcat-openbsd curl jq \
      gcc python3-dev ffmpeg libsm6 libxext6 && \
    curl -fsSL https://ollama.com/install.sh | sh; \
  else \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      docker.io \
      git build-essential pandoc gcc netcat-openbsd curl jq \
      python3-dev ffmpeg libsm6 libxext6; \
  fi && \
  rm -rf /var/lib/apt/lists/*

# === Python & pip dependencies ===
RUN pip3 install --upgrade pip
RUN pip3 install uv

ARG USE_CUDA
ARG USE_CUDA_DOCKER_VER

RUN if [ "$USE_CUDA" = "true" ]; then \
      pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/$USE_CUDA_DOCKER_VER --no-cache-dir; \
    else \
      pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir; \
    fi

COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

# === Install Python deps with a pinned pyarrow to avoid PyExtensionType error ===
RUN printf "pyarrow==20.0.0\n" > /tmp/constraints.txt \
 && uv pip install --system -r requirements.txt -c /tmp/constraints.txt --no-cache-dir

# === COPY LOCAL MODEL FILES ===
COPY ./all-MiniLM-L6-v2 /app/backend/data/cache/embedding/models/all-MiniLM-L6-v2
COPY ./whisper /app/backend/data/cache/whisper/models

# Set environment variables to point to local model paths
ENV RAG_EMBEDDING_MODEL=/app/backend/data/cache/embedding/models/all-MiniLM-L6-v2
ENV WHISPER_MODEL_DIR=/app/backend/data/cache/whisper/models
ENV WHISPER_MODEL=base

# === DEBUG: List Whisper model files in image ===
RUN ls -lh /app/backend/data/cache/whisper/models/base

# === Pre-download models for a warm start ===
RUN python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ.get('RAG_EMBEDDING_MODEL'), device='cpu')"
RUN python -c "import os; from faster_whisper import WhisperModel; model_path = os.path.join(os.environ.get('WHISPER_MODEL_DIR', '/app/backend/data/cache/whisper/models'), os.environ.get('WHISPER_MODEL', 'base')); WhisperModel(model_path, device='cpu', compute_type='int8', local_files_only=True)"
RUN python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ.get('TIKTOKEN_ENCODING_NAME','cl100k_base'))"
RUN chown -R $UID:$GID /app/backend/data/

# === Copy frontend build ===
COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json

# === Copy backend files ===
COPY --chown=$UID:$GID ./backend .

# === Group permissions (OpenShift compatibility) ===
RUN chmod -R g=u /app $HOME

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1

USER $UID:$GID

ARG BUILD_HASH
ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true

CMD [ "bash", "start.sh" ]

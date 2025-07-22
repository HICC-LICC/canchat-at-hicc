# syntax=docker/dockerfile:1

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

# Build arguments
ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL
ARG UID
ARG GID

# Environment variables
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
    RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models" \
    TIKTOKEN_ENCODING_NAME="cl100k_base" \
    TIKTOKEN_CACHE_DIR="/app/backend/data/cache/tiktoken" \
    HF_HOME="/app/backend/data/cache/embedding/models"

WORKDIR /app/backend

ENV HOME=/root

# Fix apt sources to use HTTPS (handles all .list files, avoids sed error)
RUN find /etc/apt/ -name '*.list' -exec sed -i 's|http://|https://|g' {} + || true

# Create user and group if not root
RUN if [ "$UID" -ne 0 ]; then \
      if [ "$GID" -ne 0 ]; then addgroup --gid $GID app; fi; \
      adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma \
    && echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id \
    && chown -R $UID:$GID /app $HOME

# Install system dependencies (OLLAMA branch vs default)
RUN if [ "$USE_OLLAMA" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        git build-essential pandoc netcat-openbsd curl jq \
        gcc python3-dev ffmpeg libsm6 libxext6 && \
      curl -fsSL https://ollama.com/install.sh | sh && \
      rm -rf /var/lib/apt/lists/*; \
    else \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        git build-essential pandoc gcc netcat-openbsd curl jq \
        python3-dev ffmpeg libsm6 libxext6 && \
      rm -rf /var/lib/apt/lists/*; \
    fi

COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

# Install Python dependencies and pre-download models
RUN pip3 install --upgrade pip && pip3 install uv && \
    if [ "$USE_CUDA" = "true" ]; then \
      pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/$USE_CUDA_DOCKER_VER --no-cache-dir && \
      uv pip install --system -r requirements.txt --no-cache-dir; \
    else \
      pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir && \
      uv pip install --system -r requirements.txt --no-cache-dir; \
    fi && \
    python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ.get('RAG_EMBEDDING_MODEL','sentence-transformers/all-MiniLM-L6-v2'), device='cpu')" && \
    python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ.get('WHISPER_MODEL','base'), device='cpu', compute_type='int8', download_root=os.environ.get('WHISPER_MODEL_DIR','/app/backend/data/cache/whisper/models'))" && \
    python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ.get('TIKTOKEN_ENCODING_NAME','cl100k_base'))" && \
    chown -R $UID:$GID /app/backend/data/

# Copy frontend build files
COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json

# Copy backend files
COPY --chown=$UID:$GID ./backend .

# Provide group with same permissions as user (OpenShift compatibility)
RUN chmod -R g=u /app $HOME

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1

USER $UID:$GID

ARG BUILD_HASH
ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true

CMD [ "bash", "start.sh" ]

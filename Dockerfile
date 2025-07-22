# syntax=docker/dockerfile:1

#########################
#  Build WebUI (Node)  #
#########################
ARG BUILD_HASH=dev-build

FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS build
ARG BUILD_HASH

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ENV APP_BUILD_HASH=${BUILD_HASH}
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN npm run build


############################
#  WebUI Backend (Python) #
############################
# Build args
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_CUDA_VER=cu121
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""
ARG TIKTOKEN_ENCODING_NAME=cl100k_base
ARG UID=0
ARG GID=0

# Base image
FROM python:3.12-bookworm-slim AS base

# Propagate build args
ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL
ARG TIKTOKEN_ENCODING_NAME
ARG UID
ARG GID

# Environment
ENV \
    ENV=prod \
    PORT=8080 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL} \
    RAG_EMBEDDING_MODEL=${USE_EMBEDDING_MODEL} \
    RAG_RERANKING_MODEL=${USE_RERANKING_MODEL} \
    WHISPER_MODEL=base \
    WHISPER_MODEL_DIR=/app/backend/data/cache/whisper/models \
    TIKTOKEN_ENCODING_NAME=${TIKTOKEN_ENCODING_NAME} \
    TIKTOKEN_CACHE_DIR=/app/backend/data/cache/tiktoken \
    HF_HOME=/app/backend/data/cache/embedding/models \
    DEBIAN_FRONTEND=noninteractive \
    OLLAMA_BASE_URL="/ollama" \
    OPENAI_API_BASE_URL="" \
    OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false \
    HOME=/root \
    DOCKER=true

WORKDIR /app/backend

# Create non‑root user if needed
RUN if [ "$UID" -ne 0 ]; then \
      addgroup --gid $GID app && \
      adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

# Ensure app directories exist & permissions
RUN mkdir -p $HOME/.cache/chroma \
 && echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id \
 && chown -R $UID:$GID /app $HOME

# Install OS deps + optional Ollama
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
       ca-certificates \
       git build-essential pandoc netcat-openbsd curl \
       gcc python3-dev ffmpeg libsm6 libxext6 jq \
 && if [ "$USE_OLLAMA" = "true" ]; then \
      curl -fsSL https://ollama.com/install.sh | sh; \
    fi \
 && rm -rf /var/lib/apt/lists/*

# Copy Python requirements & install
COPY --chown=$UID:$GID backend/requirements.txt ./requirements.txt

RUN pip3 install --no-cache-dir uvicorn \
 && if [ "$USE_CUDA" = "true" ]; then \
      pip3 install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/$USE_CUDA_VER; \
    else \
      pip3 install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cpu; \
    fi \
 && pip3 install --no-cache-dir -r requirements.txt \
 && python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" \
 && python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])" \
 && python -c "import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])" \
 && chown -R $UID:$GID /app/backend/data/

# Copy built frontend + backend code
COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json
COPY --chown=$UID:$GID backend ./

# OpenShift‑friendly permissions
RUN chmod -R g=u /app $HOME

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT}/health | jq -ne 'input.status == true' || exit 1

USER $UID:$GID

ARG BUILD_HASH
ENV WEBUI_BUILD_VERSION=${BUILD_HASH}

CMD ["bash", "start.sh"]

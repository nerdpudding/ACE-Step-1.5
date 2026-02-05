FROM nvidia/cuda:12.8.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies + Python 3.11 via deadsnakes PPA
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    git \
    ffmpeg \
    libsndfile1 \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Install pip for Python 3.11
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

WORKDIR /app

# === Layer 1: PyTorch (largest download, cached separately) ===
RUN pip install --no-cache-dir \
    torch==2.10.0 \
    torchaudio==2.10.0 \
    torchvision \
    --index-url https://download.pytorch.org/whl/cu128

# === Layer 2: nano-vllm (includes flash-attn + triton pre-built wheels) ===
COPY acestep/third_parts/nano-vllm/ /app/acestep/third_parts/nano-vllm/
RUN pip install --no-cache-dir /app/acestep/third_parts/nano-vllm/

# === Layer 3: Main package (editable install for _get_project_root()) ===
COPY pyproject.toml README.md /app/
COPY acestep/ /app/acestep/
COPY examples/ /app/examples/
COPY scripts/ /app/scripts/
COPY docs/ /app/docs/
COPY .env.example /app/.env.example
RUN pip install --no-cache-dir -e . \
    && pip install --no-cache-dir tensorboard python-dotenv

# Copy entrypoint
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Create mount point directories
RUN mkdir -p /app/checkpoints /app/gradio_outputs /app/lora_output /app/training_data /app/cache

EXPOSE 7860 8001

ENTRYPOINT ["/app/docker-entrypoint.sh"]

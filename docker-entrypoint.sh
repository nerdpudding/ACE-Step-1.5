#!/bin/bash
set -e

# Create output directories (in case volume mounts don't exist yet)
mkdir -p /app/checkpoints /app/gradio_outputs /app/lora_output /app/training_data /app/cache

# Download models on first run
if [ ! -d "/app/checkpoints/acestep-v15-turbo" ]; then
    echo "=== First run: downloading models ==="
    echo "This will download all available models (~15-25GB)."
    echo "Models are saved to ./checkpoints/ on your host."
    acestep-download --all
fi

# Start Gradio UI with REST API enabled
# Override by passing a command: docker compose run acestep acestep-api
exec acestep --server-name 0.0.0.0 --port 7860 --enable-api --init_service true "$@"

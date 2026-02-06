#!/bin/bash
set -e

# Create output directories (in case volume mounts don't exist yet)
mkdir -p /app/checkpoints /app/gradio_outputs /app/lora_output /app/training_data /app/cache

# Download main model on first run (turbo DiT + default LM + VAE + text encoder)
if [ ! -d "/app/checkpoints/acestep-v15-turbo" ]; then
    echo "=== First run: downloading main model (~15GB) ==="
    echo "Models are saved to ./checkpoints/ on your host."
    echo "List available models: docker compose run --rm acestep acestep-download --list"
    echo "Download specific model: docker compose run --rm acestep acestep-download --model <name>"
    acestep-download
fi

# Download configured LM model if it's not the default (1.7B) and not yet present
LM_MODEL="${ACESTEP_LM_MODEL_PATH:-acestep-5Hz-lm-1.7B}"
if [ "$LM_MODEL" != "acestep-5Hz-lm-1.7B" ] && [ ! -d "/app/checkpoints/$LM_MODEL" ]; then
    echo "=== Downloading LM model: $LM_MODEL ==="
    acestep-download --model "$LM_MODEL"
fi

# Determine startup mode
MODE="${ACESTEP_MODE:-gradio}"

case "$MODE" in
  api)
    echo "=== Starting standalone REST API on port 8001 ==="
    echo "External: http://localhost:${API_PORT:-8501}"
    echo "API docs: see docs/ai-integration/ or docs/en/API.md"
    exec acestep-api "$@"
    ;;
  gradio|*)
    echo "=== Starting Gradio UI + embedded API on port 7860 ==="
    echo "External: http://localhost:${GRADIO_PORT:-8500}"
    exec acestep --server-name 0.0.0.0 --port 7860 --enable-api --init_service true "$@"
    ;;
esac

# ACE-Step 1.5 Dockerization Plan

## 1. Claude Skills Folder Analysis (OLD_CLAUD SKILLS/)

De `.claude/` map (die je hernoemd hebt naar `OLD_CLAUD SKILLS/`) bevat **14 bestanden** die Claude Skills definieerden voor de originele repo. Deze skills gaven Claude instructies om gebruikers te helpen met:

- **`skills/acestep/SKILL.md`** - Muziek genereren via de ACE-Step API (text-to-music, lyrics, remix)
- **`skills/acestep/music-creation-guide.md`** - Gids voor effectieve muziekprompts schrijven
- **`skills/acestep-docs/SKILL.md`** - Installatie, GPU config, troubleshooting hulp
- **11 documentatiebestanden** - Kopie van de docs/ inhoud (API, GPU, Gradio, training tutorials)

**Veiligheidsanalyse: VEILIG.** Geen prompt injection, geen data-exfiltratie, geen verborgen instructies, geen obfuscatie. Het zijn legitieme technische documentatie- en instructiebestanden. De skills zijn nu al actief voor ons via de system-reminder (je ziet ze bovenaan als `acestep` en `acestep-docs`).

---

## 2. Overzicht: Wat gaan we maken?

| Bestand | Doel |
|---------|------|
| `Dockerfile` | Container image build |
| `docker-compose.yml` | Service definitie met GPU, volumes, ports, env |
| `.env.docker` | Docker-specifieke environment configuratie |
| `.dockerignore` | Onnodige bestanden uitsluiten van build context |
| `docker-entrypoint.sh` | Startup script |

---

## 3. Dockerfile

### Base Image

```
nvidia/cuda:12.8.1-runtime-ubuntu22.04
```

- **Runtime** (niet devel): Flash Attention heeft een pre-built Linux wheel (`flash_attn-2.8.3+cu128torch2.10`), dus compilatie is **niet nodig**
- Triton compileert kernels via eigen LLVM backend, geen CUDA dev headers nodig
- Scheelt ~3GB image size vs devel

### Build Stappen

1. **System deps**: `python3.11`, `python3.11-venv`, `python3-pip`, `git`, `ffmpeg`, `libsndfile1` (audio), `curl`
   - Python 3.11 via `deadsnakes` PPA (Ubuntu 22.04 heeft standaard 3.10)
2. **Werkdirectory**: `/app`
3. **Kopieer dependency bestanden eerst** (voor Docker layer caching):
   - `pyproject.toml`, `acestep/third_parts/nano-vllm/`
4. **Installeer PyTorch 2.10.0** apart van CUDA 12.8 index (grootste download, eigen cache layer):
   ```
   pip install torch==2.10.0 torchaudio==2.10.0 torchvision --index-url https://download.pytorch.org/whl/cu128
   ```
5. **Installeer nano-vllm** (lokaal pakket, bevat flash-attn + triton deps):
   ```
   pip install ./acestep/third_parts/nano-vllm/
   ```
6. **Kopieer rest van de code** en installeer hoofdpakket:
   ```
   pip install -e .
   ```
   Editable install (`-e`) is **verplicht** omdat `_get_project_root()` in [handler.py:1029-1032](acestep/handler.py#L1029-L1032) paden resolvet relatief aan de source bestanden.
7. **Installeer extra deps** die niet in pyproject.toml staan maar wel in requirements.txt:
   - `tensorboard` (voor training logging)
   - `python-dotenv` (voor .env laden)
8. **Entrypoint**: `docker-entrypoint.sh`

### Geschatte Image Size
~15-20GB (PyTorch + CUDA libs zijn het grootste deel)

---

## 4. docker-compose.yml

```yaml
services:
  acestep:
    build: .
    container_name: acestep
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=${ACESTEP_GPU_DEVICE:-0}
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    env_file:
      - .env.docker
    ports:
      - "8500:7860"   # Gradio UI
      - "8501:8001"   # REST API
    volumes:
      - ./checkpoints:/app/checkpoints
      - ./gradio_outputs:/app/gradio_outputs
      - ./lora_output:/app/lora_output
      - ./training_data:/app/training_data
      - ./cache:/app/cache
    restart: unless-stopped
    stdin_open: true
    tty: true
```

### GPU Selectie

**Alleen de RTX 4090 beschikbaar maken** via `NVIDIA_VISIBLE_DEVICES`. De gebruiker moet eerst uitzoeken welk device-ID de 4090 is:
```bash
nvidia-smi --query-gpu=index,name,memory.total --format=csv
```
Dan instellen in `.env.docker`: `ACESTEP_GPU_DEVICE=0` (of `1`).

Door slechts 1 GPU zichtbaar te maken in de container:
- Triton en Flash Attention hoeven niet met meerdere architecturen om te gaan
- Geen Ampere/Blackwell compatibiliteitsproblemen
- Container ziet het als `cuda:0`

---

## 5. Volume Mounts

| Host pad | Container pad | Inhoud |
|----------|--------------|--------|
| `./checkpoints/` | `/app/checkpoints/` | Gedownloade modellen (~15-25GB voor alle modellen) |
| `./gradio_outputs/` | `/app/gradio_outputs/` | Gegenereerde muziek (.wav bestanden) |
| `./lora_output/` | `/app/lora_output/` | Getrainde LoRA weights + checkpoints |
| `./training_data/` | `/app/training_data/` | Input audio voor LoRA training |
| `./cache/` | `/app/cache/` | HF cache, Triton cache, TorchInductor cache |

Alle mappen komen in de **repo folder** op de host, zodat je er makkelijk bij kunt.

---

## 6. .env.docker

Gebaseerd op [.env.example](.env.example) met aanpassingen voor jouw setup:

```env
# === GPU ===
ACESTEP_GPU_DEVICE=0                    # RTX 4090 (bevestigd door gebruiker)
ACESTEP_DEVICE=cuda

# === Model (beste kwaliteit voor 24GB VRAM) ===
ACESTEP_CONFIG_PATH=acestep-v15-turbo
ACESTEP_LM_MODEL_PATH=acestep-5Hz-lm-4B
ACESTEP_LM_BACKEND=vllm
ACESTEP_INIT_LLM=true

# === Download ===
ACESTEP_DOWNLOAD_SOURCE=huggingface

# === Cache directories ===
HF_HOME=/app/cache/huggingface
TRITON_CACHE_DIR=/app/cache/triton
TORCHINDUCTOR_CACHE_DIR=/app/cache/torchinductor

# === Server ===
ACESTEP_API_HOST=0.0.0.0
ACESTEP_API_PORT=8001
```

---

## 7. docker-entrypoint.sh

```bash
#!/bin/bash
set -e

# Maak output directories aan
mkdir -p /app/checkpoints /app/gradio_outputs /app/lora_output /app/training_data /app/cache

# Download modellen als ze er nog niet zijn
if [ ! -d "/app/checkpoints/acestep-v15-turbo" ]; then
    echo "Downloading models (first run)..."
    acestep-download --all
fi

# Start Gradio UI (of command override via docker-compose command:)
exec acestep --server-name 0.0.0.0 --port 7860 --enable-api --init_service true "$@"
```

De entrypoint start de Gradio UI + REST API (via `--enable-api`). De `exec` + `"$@"` pattern maakt het ook mogelijk om via `docker compose run acestep acestep-api` alleen de API server te draaien.

---

## 8. .dockerignore

```
.git
OLD_CLAUD SKILLS/
claude_plans/
*.bat
__pycache__
*.pyc
.venv
checkpoints/
gradio_outputs/
lora_output/
training_data/
cache/
*.egg-info
```

---

## 9. requirements.txt Compatibiliteit

De `requirements.txt` bevat Windows-specifieke items maar dat is **geen probleem**:
- Platform markers (`sys_platform == 'win32'`) zorgen ervoor dat pip ze automatisch overslaat op Linux
- `pyproject.toml` is de autoritaire bron en heeft correcte Linux-specifieke versies:
  - `torch==2.10.0; sys_platform == 'linux'`
  - `torchaudio==2.10.0; sys_platform == 'linux'`
- nano-vllm's pyproject.toml heeft een pre-built Linux flash-attn wheel: `flash_attn-2.8.3+cu128torch2.10-cp311-cp311-linux_x86_64.whl`
- Triton: `triton>=3.0.0; sys_platform == 'linux'` (standaard package, geen Windows fork)

**We hoeven requirements.txt NIET aan te passen.** De platform markers werken correct.

---

## 10. Model Keuze

Met 24GB VRAM (RTX 4090, "unlimited" tier):

| Component | Model | VRAM | Kwaliteit |
|-----------|-------|------|-----------|
| DiT | `acestep-v15-turbo` | ~4GB | Zeer hoog, 8 stappen, snel |
| Language Model | `acestep-5Hz-lm-4B` | ~12GB | Beste (4B parameters) |
| VAE | `vae` (automatisch) | ~1GB | - |
| Text Encoder | `Qwen3-Embedding-0.6B` (automatisch) | ~2GB | - |

**Totaal ~19GB VRAM** - past ruim in 24GB met marge voor training.

---

## 11. Bestanden die we aanmaken/wijzigen

| Bestand | Actie | Pad |
|---------|-------|-----|
| `Dockerfile` | **Nieuw** | `/ACE-Step-1.5/Dockerfile` |
| `docker-compose.yml` | **Nieuw** | `/ACE-Step-1.5/docker-compose.yml` |
| `.env.docker` | **Nieuw** | `/ACE-Step-1.5/.env.docker` |
| `.dockerignore` | **Nieuw** | `/ACE-Step-1.5/.dockerignore` |
| `docker-entrypoint.sh` | **Nieuw** | `/ACE-Step-1.5/docker-entrypoint.sh` |

Geen bestaande bestanden worden gewijzigd.

---

## 12. Verificatie

Na implementatie testen we:

1. **Build**: `docker compose build` - moet zonder errors completen
2. **GPU check**: `docker compose run --rm acestep nvidia-smi` - moet alleen de 4090 tonen
3. **Model download**: `docker compose run --rm acestep acestep-download` - downloadt naar ./checkpoints/
4. **Start UI**: `docker compose up` - Gradio UI bereikbaar op http://localhost:8500, REST API op http://localhost:8501
5. **Genereer muziek**: Via de UI een kort testfragment genereren (30s)
6. **Check output**: Verifieer dat .wav bestanden verschijnen in ./gradio_outputs/
7. **Training**: Via LoRA Training tab in de UI een kleine test-training starten
8. **Volumes**: Alle host-mappen controleren op verwachte bestanden

# API Implementation Plan — ACE-Step 1.5 Docker

> Reference: This plan relates to the **TODO** section in [README.md](../README.md#todo) — "Standalone REST API op poort 8501".

---

## Table of Contents

- [Problem Description](#problem-description)
- [Project Context for New AI Sessions](#project-context-for-new-ai-sessions)
- [Current Architecture](#current-architecture)
- [Desired End State](#desired-end-state)
- [Implementation Steps](#implementation-steps)
  - [Step 1: ACESTEP_MODE env var](#step-1-acestep_mode-env-var)
  - [Step 2: Modify docker-entrypoint.sh](#step-2-modify-docker-entrypointsh)
  - [Step 3: AI Integration Documentation](#step-3-ai-integration-documentation)
  - [Step 4: Update README](#step-4-update-readme)
  - [Step 5: Testing](#step-5-testing)
- [AI-Driven Music Generation: The End Goal](#ai-driven-music-generation-the-end-goal)
- [References and Source Files](#references-and-source-files)

---

## Problem Description

ACE-Step 1.5 has two API modes:

1. **`acestep --enable-api`** — Mounts API endpoints on the Gradio web server (port 7860 internal, 8500 external). This is the **current setup**. It works, but the API shares the port with the Web UI and lacks features that only exist in the standalone API.

2. **`acestep-api`** — Fully standalone FastAPI/Uvicorn server on port 8001 internal (8501 external). Has additional features: task queue with statistics (`/v1/stats`), `/format_input` endpoint (LLM-enhanced caption/lyrics formatting), auto-download of missing models, multi-model support.

**The problem**: The `docker-entrypoint.sh` currently only starts variant 1. Port 8501 on the host is mapped but nothing is listening. Both modes load their own models into GPU memory, so they **cannot run simultaneously** on a single GPU. The user wants to switch between modes via an env var (`ACESTEP_MODE`).

**The goal**: Get the standalone API working so an AI assistant (Claude, ChatGPT, or another LLM) can generate music via the REST API on port 8501 based on simple user instructions. For example: "Create a creative black metal song in the style of Dimmu Borgir" → the AI writes lyrics, chooses parameters, and drives the generation via the API.

---

## Project Context for New AI Sessions

> **Read this if you're new to this project.** This gives you all the context you need to implement this plan.

### What is this project?

A Docker wrapper around [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5), an open-source AI music generator. It generates complete songs (vocals, instruments, effects) from text descriptions and lyrics. Runs locally on an NVIDIA GPU.

### Key files

| File | Purpose |
|------|---------|
| `README.md` | Main documentation (Dutch), contains TODO section |
| `Dockerfile` | Container image (CUDA 12.8 + Python 3.11) |
| `docker-compose.yml` | Service definition, port mappings, volumes |
| `docker-entrypoint.sh` | Startup script, model download, start command |
| `.env` | User's personal config (not in git) |
| `.env.example` | Template with safe defaults (in git) |
| `acestep/api_server.py` | Standalone API server source (FastAPI + Uvicorn) |
| `acestep/gradio_ui/api_routes.py` | API routes mounted on Gradio server |
| `pyproject.toml` | Python package definition, console_scripts |

### User's hardware

- CPU: AMD 5800X3D, 64GB RAM
- GPU 0: NVIDIA RTX 4090 (24GB VRAM) — used by Docker
- GPU 1: NVIDIA RTX 5070 Ti (16GB, monitors only)

### Current configuration (.env)

```
ACESTEP_GPU_DEVICE=0           # RTX 4090
ACESTEP_DEVICE=cuda
ACESTEP_CONFIG_PATH=acestep-v15-turbo   # DiT model (8 steps, fast)
ACESTEP_LM_MODEL_PATH=acestep-5Hz-lm-4B  # Best LM (12GB VRAM)
ACESTEP_LM_BACKEND=vllm       # Fast inference
ACESTEP_INIT_LLM=true
GRADIO_PORT=8500
API_PORT=8501
```

### What already works

- Docker build + run: fully operational
- Model auto-download on first start
- Gradio Web UI at http://localhost:8500
- API endpoints on port 8500 (via `--enable-api`): `/health`, `/release_task`, `/query_result`, `/v1/audio`, `/v1/models`
- vllm backend with 4B LM
- Volume mounts for checkpoints, outputs, cache

### What does NOT work yet

- Standalone API on port 8501 (this plan)
- AI-driven music generation via the API (depends on the standalone API + integration docs)
- OOM risk with 4B LM + batch_size > 1 (24GB is tight)

---

## Current Architecture

```
Host                          Docker container (acestep)
─────────────────────         ─────────────────────────────────
                              docker-entrypoint.sh
                                ├── acestep-download (if needed)
                                └── exec acestep --enable-api
                                        │
:8500 ──── port map ────→ :7860   Gradio UI + embedded API
:8501 ──── port map ────→ :8001   (NOTHING — port unused)
```

### Console scripts (pyproject.toml)

```
acestep          = "acestep.acestep_v15_pipeline:main"   → Gradio UI
acestep-api      = "acestep.api_server:main"             → Standalone FastAPI
acestep-download = "acestep.model_downloader:main"       → Model downloads
```

---

## Desired End State

```
Host                          Docker container (acestep)
─────────────────────         ─────────────────────────────────
                              docker-entrypoint.sh
                                ├── acestep-download (if needed)
                                └── MODE check:
                                    ├── gradio → exec acestep --enable-api (port 7860)
                                    └── api    → exec acestep-api (port 8001)

ACESTEP_MODE=gradio:
:8500 ──── port map ────→ :7860   Gradio UI + embedded API  ✅
:8501 ──── port map ────→ :8001   (unused, that's OK)

ACESTEP_MODE=api:
:8500 ──── port map ────→ :7860   (unused, that's OK)
:8501 ──── port map ────→ :8001   Standalone REST API  ✅
```

The user switches by setting `ACESTEP_MODE=gradio` or `ACESTEP_MODE=api` in `.env`. Default: `gradio` (existing behavior).

---

## Implementation Steps

### Step 1: ACESTEP_MODE env var

**Files**: `.env.example`, `.env`

Add `ACESTEP_MODE` to both files.

**In `.env.example`** — add after the ports section:

```bash
# ==================== Mode ====================
# gradio = Web UI + embedded API on port 8500 (default)
# api    = Standalone REST API on port 8501 (for AI/script integration)
ACESTEP_MODE=gradio
```

**In `.env`** — add the same. The user can then switch to `api` when they want the standalone API.

### Step 2: Modify docker-entrypoint.sh

**File**: `docker-entrypoint.sh`

Replace the current `exec` command at the bottom with a mode switch:

```bash
# Determine startup mode
MODE="${ACESTEP_MODE:-gradio}"

case "$MODE" in
  api)
    echo "=== Starting standalone REST API on port 8001 ==="
    echo "API documentation: see docs/en/API.md"
    exec acestep-api "$@"
    ;;
  gradio|*)
    echo "=== Starting Gradio UI + embedded API on port 7860 ==="
    exec acestep --server-name 0.0.0.0 --port 7860 --enable-api --init_service true "$@"
    ;;
esac
```

**Important**: The `acestep-api` command reads its host/port from env vars `ACESTEP_API_HOST` and `ACESTEP_API_PORT`, which are already set to `0.0.0.0` and `8001` in `docker-compose.yml`. This works out-of-the-box.

The `acestep-api` command also reads `ACESTEP_CONFIG_PATH`, `ACESTEP_LM_MODEL_PATH`, `ACESTEP_LM_BACKEND`, `ACESTEP_INIT_LLM`, etc. from the environment — the same variables already in `.env`. No extra configuration needed.

### Step 3: AI Integration Documentation

**Goal**: Create tool-agnostic documentation so that *any* AI assistant, orchestrator, or agent framework can use the ACE-Step API to generate music. This is not tied to Claude — it works with ChatGPT, LangChain, custom agents, or anything that can make HTTP calls.

**Source material**: The original repo contains instruction files that were written as a "Claude Skill" but are essentially universal AI instruction documents:
- `_original_repo_old/OLD_CLAUD SKILLS/skills/acestep/SKILL.md` — API workflow, parameters, script commands
- `_original_repo_old/OLD_CLAUD SKILLS/skills/acestep/music-creation-guide.md` — How to write captions, lyrics, choose BPM/key/duration

These are valuable regardless of which AI reads them. The SKILL.md format is increasingly supported by multiple AI tools, not just Claude.

**Actions**:

1. **Move skill files to `docs/ai-integration/`**:
   ```
   docs/ai-integration/
   ├── SKILL.md                ← AI instruction set (API workflow, commands, parameters)
   ├── music-creation-guide.md ← Caption/lyrics writing guide, duration calculation, structure tags
   └── API.md                  ← Symlink or copy of the full API reference
   ```
   Update port references from 8001 → 8501 (the external Docker port).

2. **Add a section in README.md** under "REST API & AI Integratie" explaining:

   > **AI-assisted music generation**: If you want to use an AI assistant or agent to drive the API, include the instruction documents from `docs/ai-integration/` in your agent's context. These documents teach the AI how to:
   > - Transform a vague user request ("make me a black metal song") into proper API parameters
   > - Write effective captions and lyrics with correct structure tags
   > - Calculate appropriate duration, BPM, key based on genre and lyrics
   > - Call the API endpoints, poll for results, and download audio
   >
   > **How to use these with your AI tool**:
   > - **Claude Code / tools with skill support**: Point to `docs/ai-integration/SKILL.md` as a skill
   > - **System prompt / custom agent**: Copy the content of `SKILL.md` and `music-creation-guide.md` into your agent's system instructions
   > - **Orchestrator frameworks** (LangChain, CrewAI, etc.): Include the documents as tool descriptions or agent instructions
   > - **Direct API usage**: Read `docs/ai-integration/API.md` for the full endpoint reference

3. **Ensure `ACESTEP_MODE=api` is mentioned** as a prerequisite — the standalone API must be running for AI integration to work on port 8501.

4. **Keep the original files** in `_original_repo_old/OLD_CLAUD SKILLS/` as-is for reference. The new files in `docs/ai-integration/` are adapted copies with correct port numbers and Docker-specific context.

### Step 4: Update README

**File**: `README.md`

After implementation:

1. **Quick Install table**: Update the "Standalone API" row from "TODO" to working status
2. **REST API section**:
   - Document both modes clearly
   - Gradio mode (default): API on port 8500
   - API mode: standalone API on port 8501
   - Explain how to switch (`ACESTEP_MODE=api` in `.env`)
3. **Curl examples**: Show examples for both ports depending on mode
4. **Configuration reference table**: Add `ACESTEP_MODE`
5. **AI Integration section**: Replace the Claude-specific "Claude Skills" section with a tool-agnostic section pointing to `docs/ai-integration/`
6. **TODO section**: Remove or mark as completed

### Step 5: Testing

**Test 1: Gradio mode (existing behavior, regression test)**
```bash
# .env: ACESTEP_MODE=gradio (or not set at all)
docker compose down && docker compose up
# Verify: http://localhost:8500 shows Gradio UI
# Verify: curl -s http://localhost:8500/health → OK
```

**Test 2: API mode**
```bash
# .env: ACESTEP_MODE=api
docker compose down && docker compose up
# Verify: curl -s http://localhost:8501/health → {"data":{"status":"ok",...}}
# Verify: curl -s http://localhost:8501/v1/models → list of models
# Verify: curl -s http://localhost:8501/v1/stats → server statistics
```

**Test 3: Music generation via API**
```bash
# Submit task
TASK_ID=$(curl -s -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Symphonic black metal, epic orchestration, blast beats, tremolo picking",
    "lyrics": "[Intro - orchestral]\n\n[Verse 1 - aggressive]\nThrough frozen wastelands we march\nBeneath the blackened sky\nThe ancient ones await\nAs mortals fade and die\n\n[Chorus - powerful]\nWE ARE THE STORM\nWE ARE THE NIGHT\nRISING FROM DARKNESS\nINTO ETERNAL LIGHT",
    "thinking": true,
    "param_obj": {"duration": 120, "bpm": 160, "language": "en"}
  }' | jq -r '.data.task_id')

echo "Task: $TASK_ID"

# Poll result
curl -s -X POST http://localhost:8501/query_result \
  -H 'Content-Type: application/json' \
  -d "{\"task_id_list\": [\"$TASK_ID\"]}" | jq .
```

**Test 4: /format_input (standalone API only)**
```bash
curl -s -X POST http://localhost:8501/format_input \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "black metal",
    "lyrics": "Through the darkness",
    "param_obj": "{\"duration\": 180, \"language\": \"en\"}"
  }' | jq .
```

---

## AI-Driven Music Generation: The End Goal

This is what it's all about. After implementation, a user can say this to any AI assistant (Claude, ChatGPT, a LangChain agent, a custom orchestrator — anything that can read instructions and make HTTP calls):

> "I want a creative black metal song with good lyrics, in English with cool guitar solos, kind of in the style of Dimmu Borgir"

The AI (with the instructions from `docs/ai-integration/` in its context) then does the following:

### Step 1: Understanding and Planning

The AI reads `docs/ai-integration/music-creation-guide.md` and understands:
- Genre: symphonic black metal
- Reference: Dimmu Borgir → orchestral arrangements, blast beats, tremolo picking, atmospheric synths
- Language: English
- Guitar solos requested → must be in lyrics structure

### Step 2: Write Caption

The AI writes a detailed caption based on the guide:

```
Symphonic black metal, epic orchestral arrangements with full string section and choir,
blast beat drums, tremolo picked guitars, atmospheric synth pads,
aggressive male vocals alternating with clean operatic passages,
virtuoso guitar solos, dark and majestic atmosphere,
reminiscent of Dimmu Borgir's symphonic grandeur, high-fidelity studio production
```

### Step 3: Write Lyrics

The AI writes complete lyrics with structure tags, consistent with the caption:

```
[Intro - orchestral, building energy]

[Verse 1 - aggressive]
Through frozen wastelands we march on
Beneath the vast and blackened sky
The ancient ones have called our names
As mortal kingdoms fade and die

[Pre-Chorus - building energy]
The storm is rising from the deep
A thousand years of endless sleep

[Chorus - powerful, anthemic]
WE ARE THE TEMPEST, WE ARE THE NIGHT
FORGED IN THE DARKNESS, BURNING WITH LIGHT
RISE FROM THE ASHES, CONQUER THE THRONE
THIS SYMPHONIC CHAOS IS ALL WE HAVE KNOWN

[Guitar Solo - virtuoso, melodic]

[Verse 2 - aggressive]
Through halls of ice and ancient stone
The echoes of our fury ring
With blade and storm we claim the dawn
And to the void our voices sing

[Chorus - powerful, anthemic]
WE ARE THE TEMPEST, WE ARE THE NIGHT
FORGED IN THE DARKNESS, BURNING WITH LIGHT

[Bridge - orchestral, atmospheric]
Beyond the stars (beyond the stars)
Where mortals fear to tread
We write our names in fire
Among the glorious dead

[Final Chorus - explosive]
WE ARE THE TEMPEST, WE ARE THE NIGHT
FORGED IN THE DARKNESS, BURNING WITH LIGHT
RISE FROM THE ASHES, CONQUER THE THRONE
THIS SYMPHONIC CHAOS IS ALL WE HAVE KNOWN

[Outro - fade out, orchestral]
```

### Step 4: Determine Parameters

Based on the guide:
- **Duration**: 2 verses + 2 choruses + bridge + intro/outro + solo = ~180-240 seconds → 210s
- **BPM**: Black metal typically 140-180 → 160
- **Key**: Minor key fits dark metal → D Minor
- **Time signature**: 4/4 (standard for metal)
- **Thinking**: true (best quality with 4B LM)

### Step 5: API Call

The AI constructs and executes the API call:

```bash
curl -s -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Symphonic black metal, epic orchestral arrangements with full string section...",
    "lyrics": "[Intro - orchestral, building energy]\n\n[Verse 1 - aggressive]\nThrough frozen wastelands...",
    "thinking": true,
    "param_obj": {
      "duration": 210,
      "bpm": 160,
      "key_scale": "D Minor",
      "time_signature": "4",
      "language": "en"
    }
  }'
```

Then polls `/query_result` until done, and downloads the audio via `/v1/audio`.

### Step 6: Retrieve and Present Result

The AI polls until the song is ready, downloads it, and presents it to the user with a summary of what was created.

### Other Examples

**User**: "These are my favorite bands: Opeth, Tool, Porcupine Tree. Make something inspired by them."
→ AI chooses: progressive metal/rock, complex time signatures, clean+heavy dynamics, atmospheric

**User**: "Our company turns 50 this year, I want a festive song about our history"
→ AI chooses: corporate celebration, upbeat pop/rock, professional production, lyrics about milestones

**User**: "Just something chill to study to"
→ AI chooses: lo-fi, ambient, instrumental, relaxed tempo, no vocals

---

## References and Source Files

### In the repository

| File | Contents |
|------|----------|
| `acestep/api_server.py` | Full standalone API implementation (FastAPI, ~2430 lines). The `main()` function at line 2357 starts Uvicorn. The `create_app()` at line 858 initializes models and queue. |
| `acestep/gradio_ui/api_routes.py` | API routes mounted on Gradio (via `--enable-api`). Same endpoints, mounted as FastAPI router. |
| `pyproject.toml` (lines 71-72) | Console scripts: `acestep` → Gradio, `acestep-api` → standalone API |
| `docker-compose.yml` | Port mappings (8500→7860, 8501→8001), env vars, volumes |

### API documentation

| Document | Location | Contents |
|----------|----------|----------|
| API.md (comprehensive) | `_original_repo_old/OLD_CLAUD SKILLS/skills/acestep-docs/api/API.md` | Full API reference: all endpoints, parameters, examples, env vars |
| SKILL.md | `_original_repo_old/OLD_CLAUD SKILLS/skills/acestep/SKILL.md` | AI instruction set (skill format, usable by Claude and other AI tools): API workflow, script commands, config, parameter reference |
| Music Creation Guide | `_original_repo_old/OLD_CLAUD SKILLS/skills/acestep/music-creation-guide.md` | Guide for writing captions/lyrics: structure tags, vocal control, duration calculation, tips. Tool-agnostic — works as reference for any AI. |

### API endpoints (standalone `acestep-api`)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/release_task` | POST | Submit music generation task |
| `/query_result` | POST | Query task status (batch) |
| `/v1/audio?path=...` | GET | Download audio file |
| `/v1/models` | GET | Available DiT models |
| `/v1/stats` | GET | Server statistics (queue, jobs, avg time) |
| `/format_input` | POST | LLM-enhanced caption/lyrics formatting |
| `/create_random_sample` | POST | Get random sample parameters |

### Environment variables read by `acestep-api`

The standalone API automatically reads all relevant env vars. The most important:

| Var | Default | Description |
|-----|---------|-------------|
| `ACESTEP_API_HOST` | `127.0.0.1` | Bind host (already set to `0.0.0.0` in docker-compose.yml) |
| `ACESTEP_API_PORT` | `8001` | Bind port (already set to `8001` in docker-compose.yml) |
| `ACESTEP_CONFIG_PATH` | `acestep-v15-turbo` | DiT model |
| `ACESTEP_LM_MODEL_PATH` | `acestep-5Hz-lm-0.6B` | LM model (in .env: `4B`) |
| `ACESTEP_LM_BACKEND` | `vllm` | LM backend |
| `ACESTEP_INIT_LLM` | `auto` | Load LLM (in .env: `true`) |
| `ACESTEP_API_KEY` | *(empty)* | Optional API key |
| `ACESTEP_DEVICE` | `auto` | GPU device |

These are already correctly set in `.env` and `docker-compose.yml`. No extra configuration needed for the standalone API.

---

*Plan created: 2026-02-06*
*Related: README.md TODO section*

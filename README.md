# ACE-Step 1.5 - Docker Setup

[ACE-Step](https://github.com/ace-step/ACE-Step-1.5) is een open-source muziekgeneratie AI. Het genereert volledige nummers met zang, instrumenten en effecten op basis van tekstbeschrijvingen en lyrics. Ondersteunt 50+ talen, 1000+ instrumenten/stijlen, en nummers tot 10 minuten. Draait lokaal op je eigen GPU.

### Waarom deze repo?

Het originele ACE-Step project is primair gericht op directe installatie (pip/uv). Deze fork wrapt het in Docker zodat je:

- **Geen Python/CUDA dependencies op je host hoeft te installeren** - alles zit in de container
- **Reproduceerbaar** - iedereen met dezelfde image krijgt hetzelfde resultaat
- **Geïsoleerd** - geen conflicten met andere Python projecten of CUDA versies op je systeem
- **Makkelijk opruimen** - `docker compose down && docker image rm` en alles is weg

Wil je ACE-Step liever **zonder Docker** gebruiken? Clone dan direct het origineel: https://github.com/ace-step/ACE-Step-1.5. Dat project heeft uitgebreide installatie-instructies voor Windows, Linux en macOS.

### Over deze repo

Alle configuratie zit in `.env.docker` en is aanpasbaar per gebruiker. Werkt met elke NVIDIA GPU (vanaf ~4GB VRAM). Voor de volledige projectdocumentatie, architectuur en Python API: zie de [originele README](_original_repo_old/README.md) en de [docs/](docs/) map.

---

## Inhoudsopgave

- [Prerequisites](#prerequisites)
- [Quick Install](#quick-install)
- [Mappenstructuur](#mappenstructuur)
- [Modellen](#modellen)
- [GPU Configuratie](#gpu-configuratie)
- [LoRA Training](#lora-training)
- [REST API & AI Integratie](#rest-api--ai-integratie)
- [Configuratie referentie](#configuratie-referentie)
- [Handige commando's](#handige-commandos)
- [Docker bestanden](#docker-bestanden)
- [Windows / Docker Desktop](#windows--docker-desktop)
- [Achtergrond](#achtergrond)

---

## Prerequisites

- **NVIDIA GPU** met minimaal ~4GB VRAM (zie [GPU Configuratie](#gpu-configuratie) voor aanbevelingen)
- **Docker** met NVIDIA GPU support:
  - Linux: [Docker Engine](https://docs.docker.com/engine/install/) + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
  - Windows: zie [Windows / Docker Desktop](#windows--docker-desktop)
- **~30GB vrije schijfruimte**: ~10GB voor de Docker image + ~15-25GB voor de AI modellen
- **Git** (om de repo te clonen)

Controleer of Docker je GPU kan zien:
```bash
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

---

## Quick Install

### 1. Clone de repo

```bash
git clone <repo-url>
cd ACE-Step-1.5
```

### 2. Maak je configuratie aan

Kopieer het template en pas het aan voor je GPU:

```bash
cp .env.example .env.docker
```

Open `.env.docker` en controleer minimaal de `ACESTEP_LM_MODEL_PATH` instelling. Het bestand bevat een tabel die uitlegt welk model bij welke GPU past. Bij twijfel: laat `ACESTEP_INIT_LLM=auto` staan - het systeem kiest dan automatisch op basis van je VRAM.

### 3. Bouw en start

```bash
docker compose build
docker compose up
```

Bij de **eerste start** worden automatisch alle AI-modellen gedownload (~15-25GB) van HuggingFace. Dit hoeft maar 1 keer - de modellen worden opgeslagen in `./checkpoints/` op je host en blijven daar staan.

### 4. Gebruik

Na opstarten zijn er twee interfaces:

| Interface | URL | Wanneer |
|-----------|-----|---------|
| **Web UI** | http://localhost:8500 | Interactief muziek maken, parameters tweaken, LoRA trainen. Visuele interface met audiospeler en alle opties. |
| **REST API** | http://localhost:8501 | Programmatisch muziek genereren vanuit eigen code of scripts. Zie [API docs](docs/en/API.md) voor endpoints en parameters. |

Stop met `Ctrl+C` of `docker compose down`.

---

## Mappenstructuur

Alle data staat in de repo folder op je host, direct toegankelijk:

```
ACE-Step-1.5/
├── checkpoints/          ← AI modellen (auto-download, ~15-25GB)
│   ├── acestep-v15-turbo/    DiT model (muziekgeneratie)
│   ├── acestep-5Hz-lm-4B/   Language Model - beste kwaliteit
│   ├── acestep-5Hz-lm-1.7B/ Language Model - standaard
│   ├── acestep-5Hz-lm-0.6B/ Language Model - compact
│   ├── vae/                  Audio encoder/decoder
│   └── Qwen3-Embedding-0.6B/ Tekst encoder
│
├── gradio_outputs/       ← Gegenereerde muziek (.wav, 48kHz)
│
├── lora_output/          ← Getrainde LoRA weights en checkpoints
│
├── training_data/        ← Jouw input audio voor LoRA training
│
├── cache/                ← Interne caches (HuggingFace, Triton, TorchInductor)
│
├── .env.docker           ← Jouw configuratie (niet in git)
├── .env.example          ← Template voor .env.docker
├── Dockerfile            ← Container image definitie
├── docker-compose.yml    ← Service definitie
└── docker-entrypoint.sh  ← Startup script
```

---

## Modellen

ACE-Step gebruikt meerdere modellen die samenwerken:

### DiT Model (verplicht)

Het **DiT model** (`acestep-v15-turbo`) is de kern die de muziek genereert. Dit model is voor iedereen hetzelfde en gebruikt ~4GB VRAM.

### Language Model (optioneel, sterk aanbevolen)

Het **Language Model (LM)** verbetert de tekstverwerking: het begrijpt je beschrijvingen beter, kan metadata afleiden (BPM, toonsoort), en ondersteunt geavanceerde features. Er zijn drie varianten:

| Model | Parameters | VRAM | Kwaliteit | Aanbevolen voor |
|-------|-----------|------|-----------|-----------------|
| `acestep-5Hz-lm-0.6B` | 600M | ~3GB | Basis | 6-12GB GPU's |
| `acestep-5Hz-lm-1.7B` | 1.7B | ~8GB | Goed | 12-16GB GPU's |
| `acestep-5Hz-lm-4B` | 4B | ~12GB | Beste | 16GB+ GPU's |

Zonder LM draait ACE-Step in "pure DiT mode" - het genereert nog steeds muziek, maar je mist Thinking mode, Chain-of-Thought, Sample mode en Format mode.

### Overige modellen (automatisch)

| Model | VRAM | Functie |
|-------|------|---------|
| VAE | ~1GB | Converteert tussen audio en het interne latent space formaat |
| Qwen3-Embedding-0.6B | ~2GB | Verwerkt je tekstinput naar embeddings |

### Download

Modellen worden **automatisch gedownload** bij de eerste start van de container. De bron is standaard HuggingFace (instelbaar via `ACESTEP_DOWNLOAD_SOURCE` in `.env.docker`). Als HuggingFace niet bereikbaar is, wordt automatisch ModelScope als fallback gebruikt.

De modellen worden opgeslagen in `./checkpoints/` op je host (volume mount). Bij volgende starts worden ze direct geladen zonder opnieuw te downloaden.

Handmatig downloaden kan ook:
```bash
# Alle modellen
docker compose run --rm acestep acestep-download --all

# Specifiek model
docker compose run --rm acestep acestep-download --model acestep-5Hz-lm-4B

# Beschikbare modellen bekijken
docker compose run --rm acestep acestep-download --list
```

---

## GPU Configuratie

Pas in `.env.docker` het LM model aan voor je GPU:

| Je GPU (voorbeeld) | VRAM | `ACESTEP_LM_MODEL_PATH` | `ACESTEP_INIT_LLM` |
|---------------------|------|------------------------|---------------------|
| GTX 1650 / 1660 | 4-6GB | *(niet invullen)* | `false` |
| RTX 3060 / 4060 | 8GB | `acestep-5Hz-lm-0.6B` | `true` |
| RTX 3060 12GB | 12GB | `acestep-5Hz-lm-1.7B` | `true` |
| RTX 5070 Ti / 4080 | 16GB | `acestep-5Hz-lm-1.7B` | `true` |
| RTX 4090 | 24GB | `acestep-5Hz-lm-4B` | `true` |

Na wijzigen: `docker compose down && docker compose up`.

> Als je niet zeker bent, zet `ACESTEP_INIT_LLM=auto`. Het systeem detecteert dan je VRAM en kiest automatisch.

### GPU selectie

Standaard gebruikt de container je eerste GPU (`ACESTEP_GPU_DEVICE=0`). Als je meerdere GPU's hebt en een andere wilt gebruiken (bijv. omdat je primaire GPU je monitors aanstuurt), pas dan `ACESTEP_GPU_DEVICE` aan in `.env.docker`. Check met `nvidia-smi --query-gpu=index,name --format=csv` welk device-ID je GPU heeft. De container krijgt alleen die ene GPU te zien.

---

## LoRA Training

LoRA (Low-Rank Adaptation) laat je het model fine-tunen op je eigen muziek. Met slechts een paar nummers kun je een eigen stijl aanleren. Het resultaat is een klein bestand (~10-50MB) dat bovenop het basismodel werkt.

Referentie: op een RTX 3090 (12GB) duurt het trainen van 8 nummers ongeveer 1 uur.

### Workflow

1. **Audiobestanden verzamelen**: Plaats je `.wav` of `.mp3` bestanden in `./training_data/`
2. **Dataset bouwen**: Open de Web UI → **LoRA Training** tab → **Dataset Builder**
   - Voeg je audiobestanden toe
   - Annoteer ze (automatisch of handmatig) met beschrijving, genre, BPM etc.
   - Geef een dataset naam en optioneel een "activation tag" (een uniek woord dat je later in je prompt gebruikt om de aangeleerde stijl te activeren)
3. **Preprocessen**: Klik op "Preprocess" - de dataset wordt omgezet naar tensors (VAE latents + text embeddings). Dit is een eenmalige stap per dataset.
4. **Trainen**: Configureer training parameters (epochs, learning rate, LoRA rank) en start de training
5. **Gebruiken**: Laad de getrainde LoRA via het configuratiepaneel in de Web UI en genereer muziek in je eigen stijl

### Training output

- Tussentijdse checkpoints: `./lora_output/checkpoints/`
- Eindresultaat: `./lora_output/final/`

### Meer informatie

De volledige LoRA training documentatie met alle parameters, tips en best practices:
- [Gradio Guide - LoRA Training](docs/en/GRADIO_GUIDE.md#lora-training) (stap-voor-stap met screenshots)
- [Tutorial](docs/en/Tutorial.md) (achtergrond, hyperparameters en optimalisatietips)

---

## REST API & AI Integratie

De REST API (http://localhost:8501) maakt het mogelijk om muziek programmatisch te genereren. De basisflow is:

1. Dien een taak in via `POST /release_task`
2. Poll het resultaat via `POST /query_result`
3. Download de audio via de URL in het resultaat

### Snel voorbeeld

```bash
# Genereer een nummer (submit taak)
curl -s -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Upbeat electronic pop, energetic synths, female vocals",
    "lyrics": "[Verse]\nDancing through the neon lights\n[Chorus]\nWe are alive tonight",
    "param_obj": {"duration": 60, "bpm": 128, "language": "en"},
    "thinking": true
  }'
# Geeft een task_id terug

# Check status (vervang <task_id>)
curl -s -X POST http://localhost:8501/query_result \
  -H 'Content-Type: application/json' \
  -d '{"task_id_list": ["<task_id>"]}'
# status: 0 = bezig, 1 = klaar, 2 = mislukt

# Download audio via de URL in het resultaat
curl -o output.mp3 "http://localhost:8501/v1/audio?path=<pad-uit-resultaat>"
```

### Volledige API documentatie

Zie [docs/en/API.md](docs/en/API.md) voor alle endpoints, parameters, authenticatie en voorbeelden.

### AI-gestuurde muziekgeneratie (Claude Skills)

De originele repo bevatte Claude Code skills waarmee een AI-assistent de API kan aansturen om muziek te genereren via natuurlijke taal. Denk aan: "Maak een vrolijk popnummer over de zomer, 2 minuten, 120 BPM" - en Claude handelt de API calls, lyrics en parameters af.

Deze skills staan in `_original_repo_old/OLD_CLAUD SKILLS/` (afkomstig van de originele upstream repo):
- [`skills/acestep/`](_original_repo_old/OLD_CLAUD%20SKILLS/skills/acestep/) - Muziekgeneratie skill (API calls, lyrics schrijven, parameter keuze)
- [`skills/acestep-docs/`](_original_repo_old/OLD_CLAUD%20SKILLS/skills/acestep-docs/) - Setup en troubleshooting hulp
- [`skills/acestep-docs/guides/`](_original_repo_old/OLD_CLAUD%20SKILLS/skills/acestep-docs/guides/) - Gedetailleerde handleidingen (API, GPU, Gradio, inference)

---

## Configuratie referentie

Alle instellingen staan in `.env.docker`. Zie `.env.example` voor het volledige template met uitleg.

| Instelling | Default | Uitleg |
|------------|---------|--------|
| `ACESTEP_DEVICE` | `auto` | GPU selectie (`auto`, `cuda`, `cpu`) |
| `ACESTEP_CONFIG_PATH` | `acestep-v15-turbo` | DiT model |
| `ACESTEP_LM_MODEL_PATH` | `acestep-5Hz-lm-1.7B` | LM model (kies voor je VRAM) |
| `ACESTEP_LM_BACKEND` | `vllm` | `vllm` (snel) of `pt` (compatibeler) |
| `ACESTEP_INIT_LLM` | `auto` | LLM laden (`true`/`false`/`auto`) |
| `ACESTEP_DOWNLOAD_SOURCE` | `auto` | `auto`, `huggingface` of `modelscope` |
| `ACESTEP_API_HOST` | `0.0.0.0` | Server bind address |
| `ACESTEP_API_PORT` | `8001` | REST API poort (intern) |
| `ACESTEP_GPU_DEVICE` | `0` | Welke GPU (zie [GPU selectie](#gpu-selectie)) |

---

## Handige commando's

```bash
# Bouwen
docker compose build

# Starten (voorgrond)
docker compose up

# Starten (achtergrond)
docker compose up -d

# Stoppen
docker compose down

# Logs bekijken
docker compose logs -f

# GPU check
docker compose run --rm acestep nvidia-smi

# Modellen downloaden
docker compose run --rm acestep acestep-download --all

# Alleen REST API starten (zonder Web UI)
docker compose run --rm -p 8501:8001 acestep acestep-api
```

---

## Docker bestanden

| Bestand | Functie |
|---------|---------|
| `Dockerfile` | Bouwt de container image (CUDA 12.8 + Python 3.11 + dependencies) |
| `docker-compose.yml` | Service definitie: GPU, poorten, volume mounts |
| `.env.example` | Template configuratie (kopieer naar `.env.docker`) |
| `.env.docker` | Jouw configuratie (niet in git, gebruiker-specifiek) |
| `docker-entrypoint.sh` | Startup: downloadt modellen bij eerste start, start UI + API |
| `.dockerignore` | Sluit onnodige bestanden uit van de Docker build |

---

## Windows / Docker Desktop

Deze setup is gebouwd voor en getest op Linux. Op Windows met Docker Desktop (WSL2) werkt het ook, maar er zijn een paar aandachtspunten:

- **Installatie**: Volg de officiele [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/) installatie met **WSL2 backend**. Zorg dat GPU support werkt via Settings → Resources → WSL Integration.
- **`cp` commando**: Gebruik in PowerShell `copy .env.example .env.docker` in plaats van `cp`
- **Performance**: Volume mounts zijn trager op Windows/WSL2. Overweeg de repo in het WSL2 filesystem te clonen (`\\wsl$\...`) in plaats van op een Windows drive (`/mnt/c/...`)
- **Line endings**: Zorg dat `.env.docker` en `docker-entrypoint.sh` Unix line endings (LF) behouden, niet Windows (CRLF)

Verder zijn alle commando's en configuratie hetzelfde.

> Wil je liever **zonder Docker** op Windows werken? Het originele project heeft een kant-en-klare Windows portable package: https://github.com/ace-step/ACE-Step-1.5

---

## Achtergrond

De originele upstream repo bestanden (Windows .bat scripts, shell scripts, originele README) zijn verplaatst naar [`_original_repo_old/`](_original_repo_old/). De [originele README](_original_repo_old/README.md) bevat uitgebreide documentatie over de architectuur, Python API en non-Docker installatie.

De repo bevatte ook een `.claude/` map met instructiebestanden voor de Claude Code AI-assistent (nu in `_original_repo_old/OLD_CLAUD SKILLS/`). Dit is technische documentatie zodat Claude kan helpen met muziek genereren en troubleshooting.

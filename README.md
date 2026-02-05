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

Alle configuratie zit in `.env` en is aanpasbaar per gebruiker. Werkt met elke NVIDIA GPU (vanaf ~4GB VRAM). Voor de volledige projectdocumentatie, architectuur en Python API: zie de [originele README](_original_repo_old/README.md) en de [docs/](docs/) map.

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
- [Troubleshooting](#troubleshooting)
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

Het bestand `.env.example` is een template met voorbeeldwaarden. Je kopieert het naar `.env` — dat wordt jouw persoonlijke configuratie. `.env` staat in `.gitignore`, dus het wordt nooit per ongeluk naar GitHub gepusht (handig voor API keys of andere privé-instellingen).

```bash
cp .env.example .env
```

Open `.env` en controleer minimaal de `ACESTEP_LM_MODEL_PATH` instelling. Het bestand bevat een tabel die uitlegt welk model bij welke GPU past. Bij twijfel: laat `ACESTEP_INIT_LLM=auto` staan - het systeem kiest dan automatisch op basis van je VRAM.

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
├── .env           ← Jouw configuratie (niet in git)
├── .env.example          ← Template voor .env
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

Modellen worden **automatisch gedownload** bij de eerste start van de container. De bron is standaard HuggingFace (instelbaar via `ACESTEP_DOWNLOAD_SOURCE` in `.env`). Als HuggingFace niet bereikbaar is, wordt automatisch ModelScope als fallback gebruikt.

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

Pas in `.env` het LM model aan voor je GPU:

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

Standaard gebruikt de container je eerste GPU (`ACESTEP_GPU_DEVICE=0`). Als je meerdere GPU's hebt en een andere wilt gebruiken (bijv. omdat je primaire GPU je monitors aanstuurt), pas dan `ACESTEP_GPU_DEVICE` aan in `.env`. Check met `nvidia-smi --query-gpu=index,name --format=csv` welk device-ID je GPU heeft. De container krijgt alleen die ene GPU te zien.

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

Alle instellingen staan in `.env`. Zie `.env.example` voor het volledige template met uitleg.

| Instelling | Default | Uitleg |
|------------|---------|--------|
| `ACESTEP_DEVICE` | `auto` | GPU selectie (`auto`, `cuda`, `cpu`) |
| `ACESTEP_CONFIG_PATH` | `acestep-v15-turbo` | DiT model |
| `ACESTEP_LM_MODEL_PATH` | `acestep-5Hz-lm-1.7B` | LM model (kies voor je VRAM) |
| `ACESTEP_LM_BACKEND` | `vllm` | `vllm` (snel) of `pt` (compatibeler) |
| `ACESTEP_INIT_LLM` | `auto` | LLM laden (`true`/`false`/`auto`) |
| `ACESTEP_DOWNLOAD_SOURCE` | `auto` | `auto`, `huggingface` of `modelscope` |
| `GRADIO_PORT` | `8500` | Web UI poort op je host |
| `API_PORT` | `8501` | REST API poort op je host |
| `ACESTEP_GPU_DEVICE` | `0` | Welke GPU (zie [GPU selectie](#gpu-selectie)) |
| `ACESTEP_API_KEY` | *(geen)* | Optioneel. Zet een API key als je de REST API extern wilt exposen of wilt beveiligen tegen ongeautoriseerde toegang. |

Interne container-instellingen (server bind address, interne poorten, cache directories) staan vast in `docker-compose.yml` en hoef je niet aan te passen.

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

## Troubleshooting

| Probleem | Oplossing |
|----------|-----------|
| **Out of memory (OOM) error** | Kies een kleiner LM model in `.env`. Zie de GPU tier tabel. |
| **Port already in use** | Pas `GRADIO_PORT` en/of `API_PORT` aan in `.env` |
| **Model download faalt** | Probeer `ACESTEP_DOWNLOAD_SOURCE=modelscope` in `.env` |
| **Container start niet (Windows)** | Check of `docker-entrypoint.sh` Unix line endings (LF) heeft, niet CRLF |
| **GPU niet zichtbaar** | Run `docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi` om te testen of Docker je GPU ziet |

---

## Docker bestanden

Docker gebruikt twee soorten configuratie:

- **`docker-compose.yml`** beschrijft de infrastructuur: welke container, welke poorten, welke mappen worden gekoppeld. Dit is voor iedereen hetzelfde en staat in git.
- **`.env`** bevat jouw persoonlijke instellingen: welk model, welke GPU, eventueel een API key. Dit bestand staat in `.gitignore` en wordt dus nooit gedeeld — veilig voor privé-instellingen.

Bij het starten leest Docker Compose **beide bestanden**: de yml voor de structuur, en de `.env` voor jouw waarden. Zo kan iedereen dezelfde yml gebruiken met eigen instellingen.

| Bestand | In git? | Functie |
|---------|---------|---------|
| `Dockerfile` | ja | Bouwt de container image (CUDA 12.8 + Python 3.11 + dependencies) |
| `docker-compose.yml` | ja | Service definitie: GPU, poorten, volume mounts |
| `.env.example` | ja | Template met voorbeeldwaarden — kopieer naar `.env` |
| `.env` | **nee** | Jouw persoonlijke configuratie (nooit in git) |
| `docker-entrypoint.sh` | ja | Startup: downloadt modellen bij eerste start, start UI + API |
| `.dockerignore` | ja | Sluit onnodige bestanden uit van de Docker build |

---

## Windows / Docker Desktop

Deze setup is gebouwd voor en getest op Linux. Op Windows met Docker Desktop werkt het ook, maar de installatie en configuratie is complexer — vooral het werkend krijgen van GPU passthrough.

### Wat je nodig hebt

- Docker Desktop met **WSL2 backend** (niet Hyper-V)
- Werkende NVIDIA GPU drivers op Windows
- WSL2 met GPU support correct geconfigureerd

### Officiele documentatie

- [Docker Desktop installatie (Windows)](https://docs.docker.com/desktop/setup/install/windows-install/)
- [NVIDIA CUDA on WSL](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)
- [Docker Desktop GPU support](https://docs.docker.com/desktop/features/gpu/)

### Hulp nodig?

De Windows/WSL2/Docker/GPU stack heeft veel bewegende delen. Als je vastloopt, is een AI-assistent (Claude, ChatGPT, etc.) vaak de snelste manier om stap-voor-stap hulp te krijgen:

1. Geef de assistent deze hele README
2. Beschrijf je systeem (Windows versie, GPU model, wat je al geinstalleerd hebt)
3. Plak eventuele foutmeldingen
4. Vraag om stap-voor-stap begeleiding

Voorbeeldvraag: *"Ik heb Windows 11 met een RTX 3060, Docker Desktop net geinstalleerd. Ik wil dit project draaien maar weet niet of mijn GPU setup correct is. Kun je me stap voor stap helpen?"*

### Windows-specifieke aandachtspunten

- **`cp` commando**: Gebruik in PowerShell `copy .env.example .env`
- **Line endings**: Zorg dat `docker-entrypoint.sh` Unix line endings (LF) behoudt, niet Windows (CRLF). Git kan dit automatisch converteren — als de container faalt met een cryptische error, check dit eerst.
- **Performance**: Volume mounts zijn trager op Windows. Voor betere performance: clone de repo in het WSL2 filesystem in plaats van op een Windows drive.

### Alternatief: zonder Docker

Het originele project heeft een kant-en-klare **Windows portable package** die geen Docker vereist. Als je de Docker setup te complex vindt, is dit de makkelijkere route:
https://github.com/ace-step/ACE-Step-1.5

---

## Achtergrond

De originele upstream repo bestanden (Windows .bat scripts, shell scripts, originele README) zijn verplaatst naar [`_original_repo_old/`](_original_repo_old/). De [originele README](_original_repo_old/README.md) bevat uitgebreide documentatie over de architectuur, Python API en non-Docker installatie.

De repo bevatte ook een `.claude/` map met instructiebestanden voor de Claude Code AI-assistent (nu in `_original_repo_old/OLD_CLAUD SKILLS/`). Dit is technische documentatie zodat Claude kan helpen met muziek genereren en troubleshooting.

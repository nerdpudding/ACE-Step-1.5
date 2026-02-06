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
- [Changelog](#changelog)
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

Bij de **eerste start** wordt automatisch het hoofdmodel gedownload (~15GB) van HuggingFace. Dit hoeft maar 1 keer — de modellen worden opgeslagen in `./checkpoints/` op je host en blijven daar staan. Als je een ander LM model hebt geconfigureerd in `.env` (bijv. `acestep-5Hz-lm-4B`), wordt dat ook automatisch gedownload.

### 4. Gebruik

Na opstarten:

| Interface | URL | Mode | Wanneer |
|-----------|-----|------|---------|
| **Web UI + API** | http://localhost:8500 | `ACESTEP_MODE=gradio` (default) | Interactief muziek maken, parameters tweaken, LoRA trainen. API endpoints meegeleverd. |
| **Standalone API** | http://localhost:8501 | `ACESTEP_MODE=api` | Alleen REST API, geen UI. Extra features: `/v1/stats`, `/format_input`, task queue. Voor AI-integratie en scripts. |

Wissel van mode door `ACESTEP_MODE` in `.env` aan te passen en te herstarten:

```bash
docker compose down && docker compose up
# Of op de achtergrond (logs bekijken via: docker compose logs -f)
docker compose down && docker compose up -d
```

**Let op**: `docker compose down` is verplicht bij `.env` wijzigingen. Alleen `Ctrl+C` (stop) is niet genoeg — de container herstart dan met de oude instellingen. `down` verwijdert de container zodat een nieuwe wordt aangemaakt met de bijgewerkte `.env`. Je data (modellen, outputs, cache) blijft behouden — dat zijn mappen op je host, geen onderdeel van de container.

Beide modes laden hun eigen modellen in GPU geheugen — ze kunnen niet tegelijk draaien op dezelfde GPU.

---

## Mappenstructuur

Alle data staat in de repo folder op je host, direct toegankelijk:

```
ACE-Step-1.5/
├── checkpoints/          ← AI modellen (auto-download bij eerste start)
│   ├── acestep-v15-turbo/    DiT model (muziekgeneratie)
│   ├── acestep-5Hz-lm-*/     Language Model (afh. van ACESTEP_LM_MODEL_PATH in .env)
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

ACE-Step gebruikt meerdere modellen die samenwerken. Bij de eerste start wordt het **hoofdmodel** automatisch gedownload (~15GB). Extra modellen kun je later bijdownloaden.

### DiT Model (muziekgeneratie)

Het DiT model is de kern die de muziek genereert (~4GB VRAM). Alle varianten gebruiken even veel VRAM — het verschil zit in snelheid, kwaliteit en features. Stel in via `ACESTEP_CONFIG_PATH` in `.env`.

| Model | Steps | Snelheid | Kwaliteit | LoRA training | Wanneer gebruiken |
|-------|-------|----------|-----------|--------------|-------------------|
| **`acestep-v15-turbo`** | 8 | Snel | Zeer hoog | Gemiddeld | **Default. Aanbevolen voor de meeste gebruikers.** Beste balans tussen snelheid en kwaliteit. |
| `acestep-v15-sft` | 50 | Langzaam | Hoog | Makkelijk | Als je makkelijker wilt fine-tunen of meer controle wilt over het resultaat. |
| `acestep-v15-base` | 50 | Langzaam | Medium | Makkelijk | Meeste diversiteit en extra features (Extract, Lego, Complete). Beste startpunt voor LoRA training. |

Er zijn ook experimentele turbo-varianten met andere noise schedules: `acestep-v15-turbo-shift1`, `acestep-v15-turbo-shift3` en `acestep-v15-turbo-continuous`. Deze zijn voor gevorderd gebruik.

Alleen `acestep-v15-turbo` wordt automatisch gedownload. Andere modellen kun je bijdownloaden (zie [Download](#download)) en selecteren via `ACESTEP_CONFIG_PATH` in `.env` of via de Web UI.

### Language Model (optioneel, sterk aanbevolen)

Het **Language Model (LM)** verbetert de tekstverwerking: het begrijpt je beschrijvingen beter, kan metadata afleiden (BPM, toonsoort), en ondersteunt geavanceerde features. Er zijn drie varianten:

| Model | Parameters | VRAM | Kwaliteit | Aanbevolen voor |
|-------|-----------|------|-----------|-----------------|
| `acestep-5Hz-lm-0.6B` | 600M | ~3GB | Basis | 6-12GB GPU's |
| **`acestep-5Hz-lm-1.7B`** | 1.7B | ~8GB | Goed | 12-16GB GPU's |
| `acestep-5Hz-lm-4B` | 4B | ~12GB | Beste | 16GB+ GPU's |

`acestep-5Hz-lm-1.7B` wordt automatisch gedownload met het hoofdmodel. Als je in `.env` een ander LM model configureert (bijv. `acestep-5Hz-lm-4B`), wordt dat automatisch bijgedownload bij de volgende start.

Zonder LM draait ACE-Step in "pure DiT mode" — het genereert nog steeds muziek, maar je mist Thinking mode, Chain-of-Thought, Sample mode en Format mode.

### Overige modellen (automatisch)

| Model | VRAM | Functie |
|-------|------|---------|
| VAE | ~1GB | Converteert tussen audio en het interne latent space formaat |
| Qwen3-Embedding-0.6B | ~2GB | Verwerkt je tekstinput naar embeddings |

Deze worden automatisch gedownload als onderdeel van het hoofdmodel.

### Download

Bij de **eerste start** downloadt de container automatisch het hoofdmodel (~15GB) van HuggingFace. Dit bevat: `acestep-v15-turbo` + `acestep-5Hz-lm-1.7B` + VAE + text encoder. Als je in `.env` een ander LM model hebt geconfigureerd, wordt dat ook automatisch gedownload.

De bron is standaard HuggingFace (instelbaar via `ACESTEP_DOWNLOAD_SOURCE` in `.env`). Als HuggingFace niet bereikbaar is, wordt automatisch ModelScope als fallback gebruikt.

Alle modellen worden opgeslagen in `./checkpoints/` op je host (volume mount). Bij volgende starts worden ze direct geladen zonder opnieuw te downloaden.

Extra modellen handmatig downloaden:
```bash
# Bekijk alle beschikbare modellen
docker compose run --rm acestep acestep-download --list

# Download een specifiek model
docker compose run --rm acestep acestep-download --model acestep-v15-base
docker compose run --rm acestep acestep-download --model acestep-5Hz-lm-4B

# Download alles (alle DiT varianten + alle LM modellen, ~50GB+)
docker compose run --rm acestep acestep-download --all
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

### Wat is LoRA?

LoRA (Low-Rank Adaptation) laat je het model fine-tunen op je eigen muziek zonder het hele model opnieuw te trainen. Je leert het model een specifieke stijl, artiest of geluid aan met een paar nummers. Het resultaat is een klein bestand (~10-50MB) dat je bovenop het basismodel laadt — je kunt het aan- en uitzetten.

**Wanneer gebruiken:**
- Je wilt muziek genereren in een specifieke stijl (bijv. "klink als mijn band")
- Je wilt een bepaald instrument of geluid nauwkeuriger reproduceren
- Je wilt consistent een bepaald genre of sound genereren

### Welk DiT model voor training?

**Train altijd op hetzelfde model dat je ook voor generatie gebruikt.** Een LoRA leert aanpassingen relatief aan de weights van het model waarop je traint. Op een ander model laden kan technisch (de architectuur is identiek), maar de resultaten zijn dan onvoorspelbaar.

| Scenario | DiT model | Waarom |
|----------|-----------|--------|
| Snel genereren met LoRA | `acestep-v15-turbo` | Train en genereer op turbo. Snelste resultaat (8 steps). |
| Makkelijker trainen | `acestep-v15-base` | Leert stijlen sneller aan, meer diversiteit. Maar: langzamer bij generatie (50 steps), en de LoRA werkt alleen goed op base. |
| Balans kwaliteit/training | `acestep-v15-sft` | Hogere basiskwaliteit dan base, makkelijker te trainen dan turbo. |

De meeste gebruikers willen turbo voor snelle generatie → train dan ook op turbo.

### Model wisselen

Als je een ander DiT model wilt gebruiken (bijv. `base` voor LoRA training), heb je twee opties:

**Optie 1: Via de Web UI (geen herstart nodig)**
1. Open de Web UI → kies een ander model in de "Checkpoint" dropdown
2. Klik op "Initialize Service" om het nieuwe model te laden

**Optie 2: Via `.env` (herstart nodig)**
1. Pas `ACESTEP_CONFIG_PATH` aan in `.env` (bijv. `acestep-v15-base`)
2. `docker compose down && docker compose up`

Als het model nog niet gedownload is:
```bash
docker compose run --rm acestep acestep-download --model acestep-v15-base
```

### Workflow

1. **Audiobestanden verzamelen**: Plaats je `.wav` of `.mp3` bestanden in `./training_data/`
2. **Dataset bouwen**: Open de Web UI → **LoRA Training** tab → **Dataset Builder**
   - Voeg je audiobestanden toe
   - Annoteer ze (automatisch of handmatig) met beschrijving, genre, BPM etc.
   - Geef een dataset naam en een "activation tag" — een uniek woord dat je later in je prompt gebruikt om de aangeleerde stijl te activeren (bijv. "mystijl")
3. **Preprocessen**: Klik op "Preprocess" — de dataset wordt omgezet naar tensors. Dit is een eenmalige stap per dataset.
4. **Trainen**: Configureer training parameters (epochs, learning rate, LoRA rank) en start de training
5. **Gebruiken**: Ga naar het generatie-scherm, laad je LoRA via het configuratiepaneel, en gebruik je activation tag in de prompt

### Training output

- Tussentijdse checkpoints: `./lora_output/checkpoints/`
- Eindresultaat: `./lora_output/final/`

### Meer informatie

De volledige LoRA training documentatie met alle parameters, tips en best practices:
- [Gradio Guide - LoRA Training](docs/en/GRADIO_GUIDE.md#lora-training) (stap-voor-stap met screenshots)
- [Tutorial](docs/en/Tutorial.md) (achtergrond, hyperparameters en optimalisatietips)

---

## REST API & AI Integratie

De REST API maakt het mogelijk om muziek programmatisch te genereren. Er zijn twee modes:

| Mode | Poort | Beschikbare endpoints |
|------|-------|-----------------------|
| **Gradio** (default) | 8500 | `/release_task`, `/query_result`, `/v1/audio`, `/v1/models`, `/health` |
| **Standalone API** | 8501 | Alles hierboven + `/v1/stats`, `/format_input`, `/create_random_sample` |

De basisflow is in beide modes hetzelfde:

1. Dien een taak in via `POST /release_task`
2. Poll het resultaat via `POST /query_result`
3. Download de audio via de URL in het resultaat

### Snel voorbeeld

```bash
# Poort hangt af van je mode:
#   ACESTEP_MODE=gradio → poort 8500
#   ACESTEP_MODE=api    → poort 8501
PORT=8501  # pas aan naar jouw mode

# Genereer een nummer (submit taak)
curl -s -X POST http://localhost:$PORT/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Upbeat electronic pop, energetic synths, female vocals",
    "lyrics": "[Verse]\nDancing through the neon lights\n[Chorus]\nWe are alive tonight",
    "param_obj": {"duration": 60, "bpm": 128, "language": "en"},
    "thinking": true
  }'
# Geeft een task_id terug

# Check status (vervang <task_id>)
curl -s -X POST http://localhost:$PORT/query_result \
  -H 'Content-Type: application/json' \
  -d '{"task_id_list": ["<task_id>"]}'
# status: 0 = bezig, 1 = klaar, 2 = mislukt

# Download audio via de URL in het resultaat
curl -o output.mp3 "http://localhost:$PORT/v1/audio?path=<pad-uit-resultaat>"
```

### Volledige API documentatie

Zie [docs/ai-integration/API.md](docs/ai-integration/API.md) voor alle endpoints, parameters, authenticatie en voorbeelden.

### AI-gestuurde muziekgeneratie

Wil je een AI-assistent of agent de API laten aansturen om muziek te genereren? Bijvoorbeeld: *"Maak een creatief black metal nummer in de stijl van Dimmu Borgir"* — en de AI schrijft lyrics, kiest parameters, en stuurt de API calls aan.

Hiervoor zijn instructiedocumenten beschikbaar in [`docs/ai-integration/`](docs/ai-integration/):

| Document | Wat het bevat |
|----------|---------------|
| [`SKILL.md`](docs/ai-integration/SKILL.md) | AI instructieset: API workflow, endpoints, parameters, generatie-modes. Bruikbaar als skill, system prompt, of agent instructie. |
| [`music-creation-guide.md`](docs/ai-integration/music-creation-guide.md) | Muziekcreatie kennis: caption schrijven, lyrics met structure tags, BPM/key/duur berekenen, tips. |
| [`API.md`](docs/ai-integration/API.md) | Volledige API referentie met alle endpoints en voorbeelden. |

**Hoe te gebruiken met je AI tool**:
- **Claude Code / tools met skill support**: Verwijs naar `docs/ai-integration/SKILL.md` als skill
- **System prompt / custom agent**: Kopieer de inhoud van `SKILL.md` en `music-creation-guide.md` naar de system instructies van je agent
- **Orchestrator frameworks** (LangChain, CrewAI, etc.): Neem de documenten op als tool descriptions of agent instructies
- **Direct API gebruik**: Zie `docs/ai-integration/API.md`

**Let op**: Voor AI-integratie op poort 8501 moet `ACESTEP_MODE=api` staan in `.env`.

---

## Configuratie referentie

Alle instellingen staan in `.env`. Zie `.env.example` voor het volledige template met uitleg.

| Instelling | Default | Uitleg |
|------------|---------|--------|
| `ACESTEP_MODE` | `gradio` | `gradio` = Web UI + API op poort 8500, `api` = standalone API op poort 8501 |
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

# Wisselen naar standalone API mode
# Zet ACESTEP_MODE=api in .env, daarna:
docker compose down && docker compose up
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
| `docker-entrypoint.sh` | ja | Startup script: downloadt modellen bij eerste start, kiest op basis van `ACESTEP_MODE` welke server gestart wordt (Gradio of standalone API) |
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

## Changelog

### Standalone REST API op poort 8501

**Status**: Geimplementeerd. Kies je mode via `ACESTEP_MODE` in `.env`.

- [x] `ACESTEP_MODE` env var toegevoegd aan `.env.example` en `.env`
- [x] `docker-entrypoint.sh` aangepast met mode switch (gradio/api)
- [x] REST API sectie in README bijgewerkt met beide modes
- [x] AI-integratie documentatie aangemaakt in `docs/ai-integration/`
- [x] API voorbeelden aangepast naar correcte poort per mode
- [x] Configuratie referentie tabel uitgebreid met `ACESTEP_MODE`

---

## Achtergrond

De originele upstream repo bestanden (Windows .bat scripts, shell scripts, originele README) zijn verplaatst naar [`_original_repo_old/`](_original_repo_old/). De [originele README](_original_repo_old/README.md) bevat uitgebreide documentatie over de architectuur, Python API en non-Docker installatie.

De repo bevatte ook een `.claude/` map met instructiebestanden voor de Claude Code AI-assistent (nu in `_original_repo_old/OLD_CLAUD SKILLS/`). Dit is technische documentatie zodat Claude kan helpen met muziek genereren en troubleshooting.

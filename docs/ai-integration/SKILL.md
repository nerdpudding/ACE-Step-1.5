---
name: acestep
description: Use ACE-Step API to generate music from text descriptions and lyrics. Supports text-to-music, lyrics generation, audio continuation, and audio repainting. Use this skill when users mention generating music, creating songs, music production, remix, or audio continuation.
---

# ACE-Step Music Generation — AI Integration

Use ACE-Step V1.5 REST API for AI-driven music generation. This document provides instructions for any AI assistant, agent framework, or orchestrator that can make HTTP calls.

## Prerequisites

- ACE-Step Docker container running in **API mode** (`ACESTEP_MODE=api` in `.env`)
- API available at `http://localhost:8501`
- Tools: `curl` and `jq` (for shell-based workflows)

### Health Check

```bash
curl -s http://localhost:8501/health
# Should return: {"data":{"status":"ok","service":"ACE-Step API","version":"1.0"},...}
```

If health check fails, the container may be in `gradio` mode or not running. Check with `docker compose ps` and verify `ACESTEP_MODE=api` in `.env`.

---

## Workflow

For user requests involving music generation, follow this workflow:

1. **Understand the request** — What genre, mood, language, vocal style does the user want?
2. **Consult the [Music Creation Guide](./music-creation-guide.md)** — Use it to write captions, lyrics, and choose parameters
3. **Write a detailed caption** — Style, instruments, emotion, vocal characteristics, production quality
4. **Write complete lyrics with structure tags** — `[Verse]`, `[Chorus]`, `[Bridge]`, etc.
5. **Calculate parameters** — Duration (based on lyrics length), BPM (based on genre), key, time signature
6. **Submit the task** via `POST /release_task`
7. **Poll for results** via `POST /query_result` until `status` is `1` (success) or `2` (failed)
8. **Download audio** via the URL in the result

### Generation Modes

| Mode | When to Use | How |
|------|-------------|-----|
| **Caption** (Recommended) | For vocal songs — write lyrics yourself first | `prompt` + `lyrics` + `thinking: true` |
| **Simple/Description** | Quick exploration, LM generates everything | `sample_mode: true` + `sample_query` |
| **Random** | Random generation for inspiration | `POST /create_random_sample` |

**Always prefer Caption mode** for the best results. Write the lyrics yourself rather than letting the LM generate them.

---

## API Endpoints

All responses are wrapped: `{"data": <payload>, "code": 200, "error": null, "timestamp": ...}`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/release_task` | POST | Submit music generation task |
| `/query_result` | POST | Query task status (batch) |
| `/v1/audio?path={path}` | GET | Download audio file |
| `/v1/models` | GET | List available DiT models |
| `/v1/stats` | GET | Server statistics (queue, jobs, avg time) |
| `/format_input` | POST | LLM-enhanced caption/lyrics formatting |
| `/create_random_sample` | POST | Get random sample parameters |

---

## Quick Example: Full Generation Flow

```bash
# 1. Submit task
TASK_ID=$(curl -s -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "Symphonic black metal, epic orchestral arrangements, blast beats, tremolo picking, aggressive male vocals, dark atmosphere",
    "lyrics": "[Intro - orchestral]\n\n[Verse 1 - aggressive]\nThrough frozen wastelands we march\nBeneath the blackened sky\nThe ancient ones await\nAs mortals fade and die\n\n[Chorus - powerful]\nWE ARE THE STORM\nWE ARE THE NIGHT\nRISING FROM DARKNESS\nINTO ETERNAL LIGHT\n\n[Outro - fade out]",
    "thinking": true,
    "param_obj": {
      "duration": 120,
      "bpm": 160,
      "key_scale": "D Minor",
      "time_signature": "4",
      "language": "en"
    }
  }' | jq -r '.data.task_id')

echo "Task: $TASK_ID"

# 2. Poll for result (repeat until status != 0)
curl -s -X POST http://localhost:8501/query_result \
  -H 'Content-Type: application/json' \
  -d "{\"task_id_list\": [\"$TASK_ID\"]}" | jq .

# 3. Download audio (use the file URL from the result)
# curl -o output.mp3 "http://localhost:8501/v1/audio?path=<path-from-result>"
```

---

## Request Parameters (`/release_task`)

### Core Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `prompt` | string | `""` | Music style description (alias: `caption`) |
| `lyrics` | string | `""` | **Complete lyrics** — pass ALL lyrics without omission. Use `[inst]` or `[Instrumental]` for instrumental sections |
| `thinking` | bool | `false` | Enable 5Hz LM for audio code generation (higher quality, recommended) |
| `sample_mode` | bool | `false` | Enable description-driven mode (LM generates everything) |
| `sample_query` | string | `""` | Description for sample mode (alias: `description`, `desc`) |
| `use_format` | bool | `false` | Use LM to enhance caption/lyrics |
| `model` | string | - | DiT model name (use `/v1/models` to list) |
| `batch_size` | int | `1` | Number of audio files to generate (max 8) |

### Music Attributes (in `param_obj` or top-level)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `duration` | float | - | Duration in seconds (alias: `audio_duration`) |
| `bpm` | int | - | Tempo (30-300) |
| `key_scale` | string | `""` | Key (e.g., "C Major", "D Minor") |
| `time_signature` | string | `""` | Time signature ("2", "3", "4", "6" for 2/4, 3/4, 4/4, 6/8) |
| `language` | string | `"en"` | Vocal language (alias: `vocal_language`) |
| `audio_format` | string | `"mp3"` | Output format (mp3/wav/flac) |

### Generation Control

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `inference_steps` | int | `8` | Diffusion steps (turbo: 1-20, base: 1-200) |
| `guidance_scale` | float | `7.0` | CFG scale (base model only) |
| `seed` | int | `-1` | Random seed (-1 for random) |

### Audio Task Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `task_type` | string | `"text2music"` | text2music / cover / repaint / continuation |
| `src_audio_path` | string | - | Source audio path (for continuation/repainting) |
| `repainting_start` | float | `0.0` | Repainting start position (seconds) |
| `repainting_end` | float | - | Repainting end position (seconds) |

### Query Result Response

```json
{
  "data": [{
    "task_id": "xxx",
    "status": 1,
    "result": "[{\"file\":\"/v1/audio?path=...\",\"metas\":{\"bpm\":120,\"duration\":60,\"keyscale\":\"C Major\"}}]"
  }]
}
```

Status codes: `0` = processing, `1` = success, `2` = failed

**Important**: The `result` field is a JSON string that must be parsed. It contains an array of result objects, each with a `file` field containing the download URL.

---

## Tips for AI Assistants

1. **Always use `thinking: true`** — This enables the 5Hz LM for much better quality
2. **Write lyrics yourself** — Don't rely on `sample_mode` for serious requests. Write complete, well-structured lyrics with proper structure tags
3. **Be generous with duration** — Too short is worse than too long. Calculate based on lyrics length (3-5 sec per line + intro/outro)
4. **Match caption and lyrics** — Instruments mentioned in caption should appear as tags in lyrics. Don't contradict yourself
5. **Use uppercase for intensity** — `WE ARE THE CHAMPIONS` generates louder, more powerful vocals than `we are the champions`
6. **Poll patiently** — Generation can take 30 seconds to several minutes depending on duration and model settings. Poll every 5-10 seconds
7. **Check actual output** — When `thinking: true`, the LM may enhance your caption/lyrics. Check the result JSON for what was actually used

For detailed guidance on writing captions, lyrics, and choosing parameters, see [music-creation-guide.md](./music-creation-guide.md).
For the complete API reference with all parameters and examples, see [API.md](./API.md).

# ACE-Step API Reference

> Complete API reference for the ACE-Step standalone REST API (`acestep-api`).
> Running on `http://localhost:8501` when `ACESTEP_MODE=api` in `.env`.

---

## Basic Workflow

1. Call `POST /release_task` to submit a task and obtain a `task_id`.
2. Call `POST /query_result` to batch query task status until `status` is `1` (succeeded) or `2` (failed).
3. Download audio files via `GET /v1/audio?path=...` URLs returned in the result.

---

## Table of Contents

- [Authentication](#1-authentication)
- [Response Format](#2-response-format)
- [Task Status](#3-task-status)
- [Create Generation Task](#4-create-generation-task)
- [Batch Query Task Results](#5-batch-query-task-results)
- [Format Input](#6-format-input)
- [Get Random Sample](#7-get-random-sample)
- [List Available Models](#8-list-available-models)
- [Server Statistics](#9-server-statistics)
- [Download Audio Files](#10-download-audio-files)
- [Health Check](#11-health-check)
- [Environment Variables](#12-environment-variables)

---

## 1. Authentication

Optional API key authentication. When enabled, a valid key must be provided.

**Method A: ai_token in request body**

```json
{
  "ai_token": "your-api-key",
  "prompt": "upbeat pop song"
}
```

**Method B: Authorization header**

```bash
curl -X POST http://localhost:8501/release_task \
  -H 'Authorization: Bearer your-api-key' \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "upbeat pop song"}'
```

Configure via `ACESTEP_API_KEY` in `.env` or as env var.

---

## 2. Response Format

All responses use a unified wrapper:

```json
{
  "data": { ... },
  "code": 200,
  "error": null,
  "timestamp": 1700000000000,
  "extra": null
}
```

| Field | Type | Description |
|-------|------|-------------|
| `data` | any | Actual response data |
| `code` | int | Status code (200=success) |
| `error` | string | Error message (null on success) |
| `timestamp` | int | Response timestamp (ms) |
| `extra` | any | Extra information (usually null) |

---

## 3. Task Status

| Status Code | Name | Description |
|-------------|------|-------------|
| `0` | queued/running | Task is queued or in progress |
| `1` | succeeded | Generation succeeded, result ready |
| `2` | failed | Generation failed |

---

## 4. Create Generation Task

- **URL**: `/release_task`
- **Method**: `POST`
- **Content-Type**: `application/json`, `multipart/form-data`, or `application/x-www-form-urlencoded`

### Parameter Naming

The API supports both **snake_case** and **camelCase**:
- `audio_duration` / `duration` / `audioDuration`
- `key_scale` / `keyscale` / `keyScale`
- `time_signature` / `timesignature` / `timeSignature`
- `sample_query` / `sampleQuery` / `description` / `desc`

Metadata can be passed in a nested object (`param_obj`, `metas`, `metadata`, or `user_metadata`).

### Basic Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `prompt` | string | `""` | Music description prompt (alias: `caption`) |
| `lyrics` | string | `""` | Lyrics content |
| `thinking` | bool | `false` | Use 5Hz LM for audio code generation (recommended) |
| `vocal_language` | string | `"en"` | Lyrics language (en, zh, ja, etc.) |
| `audio_format` | string | `"mp3"` | Output format (mp3, wav, flac) |

### Sample/Description Mode

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sample_mode` | bool | `false` | Enable random sample generation mode |
| `sample_query` | string | `""` | Natural language description (aliases: `description`, `desc`) |
| `use_format` | bool | `false` | Use LM to enhance caption/lyrics (alias: `format`) |

### Multi-Model Support

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | string | null | Select DiT model (use `/v1/models` to list) |

### `thinking` Semantics

- `thinking=false`: DiT runs in text2music mode without LM codes
- `thinking=true`: 5Hz LM generates audio codes for enhanced quality (lm-dit behavior)

### Music Attributes

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bpm` | int | null | Tempo (30-300) |
| `key_scale` | string | `""` | Key/scale (e.g., "C Major", "Am") |
| `time_signature` | string | `""` | Time signature (2, 3, 4, 6) |
| `audio_duration` | float | null | Duration in seconds (10-600). Aliases: `duration`, `target_duration` |

### Generation Control

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `inference_steps` | int | `8` | Diffusion steps. Turbo: 1-20 (rec. 8). Base: 1-200 (rec. 32-64) |
| `guidance_scale` | float | `7.0` | CFG scale (base model only) |
| `use_random_seed` | bool | `true` | Use random seed |
| `seed` | int | `-1` | Specific seed (when use_random_seed=false) |
| `batch_size` | int | `2` | Batch generation count (max 8) |

### Advanced DiT Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `shift` | float | `3.0` | Timestep shift factor (1.0-5.0, base models only) |
| `infer_method` | string | `"ode"` | Diffusion method: `"ode"` (Euler, faster) or `"sde"` (stochastic) |
| `timesteps` | string | null | Custom timesteps (overrides inference_steps) |

### 5Hz LM Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `lm_temperature` | float | `0.85` | Sampling temperature |
| `lm_cfg_scale` | float | `2.5` | CFG scale |
| `lm_top_p` | float | `0.9` | Top-p |
| `lm_repetition_penalty` | float | `1.0` | Repetition penalty |

### LM CoT (Chain-of-Thought)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `use_cot_caption` | bool | `true` | Let LM rewrite/enhance caption via CoT |
| `use_cot_language` | bool | `true` | Let LM detect vocal language via CoT |
| `constrained_decoding` | bool | `true` | Enable FSM-based constrained decoding |

### Audio Task Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `task_type` | string | `"text2music"` | text2music, cover, repaint, lego, extract, complete |
| `src_audio_path` | string | null | Source audio path |
| `repainting_start` | float | `0.0` | Repainting start time (seconds) |
| `repainting_end` | float | null | Repainting end time (seconds) |
| `audio_cover_strength` | float | `1.0` | Cover strength (0.0-1.0) |

### Response

```json
{
  "data": {
    "task_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "queued",
    "queue_position": 1
  },
  "code": 200,
  "error": null,
  "timestamp": 1700000000000
}
```

### Examples

```bash
# Basic generation
curl -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "upbeat pop song",
    "lyrics": "[Verse]\nHello world\n[Chorus]\nSinging along",
    "thinking": true,
    "param_obj": {"duration": 60, "bpm": 120, "language": "en"}
  }'

# Description-driven (LM generates everything)
curl -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "sample_query": "a soft Bengali love song for a quiet evening",
    "thinking": true
  }'

# With format enhancement
curl -X POST http://localhost:8501/release_task \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "pop rock",
    "lyrics": "[Verse 1]\nWalking down the street...",
    "use_format": true,
    "thinking": true
  }'
```

---

## 5. Batch Query Task Results

- **URL**: `/query_result`
- **Method**: `POST`

### Request

| Parameter | Type | Description |
|-----------|------|-------------|
| `task_id_list` | array | List of task IDs to query |

### Response

```json
{
  "data": [
    {
      "task_id": "550e8400-...",
      "status": 1,
      "result": "[{\"file\":\"/v1/audio?path=...\",\"metas\":{\"bpm\":120,\"duration\":60,\"keyscale\":\"C Major\"},\"prompt\":\"...\",\"lyrics\":\"...\",\"seed_value\":\"12345\",\"lm_model\":\"acestep-5Hz-lm-4B\",\"dit_model\":\"acestep-v15-turbo\"}]"
    }
  ]
}
```

**Note**: `result` is a JSON string that must be parsed.

### Example

```bash
curl -X POST http://localhost:8501/query_result \
  -H 'Content-Type: application/json' \
  -d '{"task_id_list": ["550e8400-e29b-41d4-a716-446655440000"]}'
```

---

## 6. Format Input

- **URL**: `/format_input`
- **Method**: `POST`

Uses LLM to enhance and format caption and lyrics.

### Request

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `prompt` | string | `""` | Music description |
| `lyrics` | string | `""` | Lyrics content |
| `temperature` | float | `0.85` | LM sampling temperature |
| `param_obj` | string (JSON) | `"{}"` | Metadata (duration, bpm, key, time_signature, language) |

### Response

```json
{
  "data": {
    "caption": "Enhanced music description",
    "lyrics": "Formatted lyrics...",
    "bpm": 120,
    "key_scale": "C Major",
    "time_signature": "4",
    "duration": 180,
    "vocal_language": "en"
  }
}
```

### Example

```bash
curl -X POST http://localhost:8501/format_input \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "pop rock",
    "lyrics": "Walking down the street",
    "param_obj": "{\"duration\": 180, \"language\": \"en\"}"
  }'
```

---

## 7. Get Random Sample

- **URL**: `/create_random_sample`
- **Method**: `POST`

Returns random sample parameters from pre-loaded example data.

### Request

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sample_type` | string | `"simple_mode"` | `"simple_mode"` or `"custom_mode"` |

### Example

```bash
curl -X POST http://localhost:8501/create_random_sample \
  -H 'Content-Type: application/json' \
  -d '{"sample_type": "simple_mode"}'
```

---

## 8. List Available Models

- **URL**: `/v1/models`
- **Method**: `GET`

```bash
curl http://localhost:8501/v1/models
```

---

## 9. Server Statistics

- **URL**: `/v1/stats`
- **Method**: `GET`

Returns queue size, job counts, average job duration.

```bash
curl http://localhost:8501/v1/stats
```

---

## 10. Download Audio Files

- **URL**: `/v1/audio`
- **Method**: `GET`

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | URL-encoded path to the audio file |

```bash
curl "http://localhost:8501/v1/audio?path=%2Ftmp%2Fapi_audio%2Fabc123.mp3" -o output.mp3
```

---

## 11. Health Check

- **URL**: `/health`
- **Method**: `GET`

```bash
curl http://localhost:8501/health
```

---

## 12. Environment Variables

### Server

| Variable | Default | Description |
|----------|---------|-------------|
| `ACESTEP_API_HOST` | `127.0.0.1` | Bind host (set to `0.0.0.0` in docker-compose.yml) |
| `ACESTEP_API_PORT` | `8001` | Bind port (set to `8001` in docker-compose.yml) |
| `ACESTEP_API_KEY` | (empty) | API authentication key |
| `ACESTEP_API_WORKERS` | `1` | API worker thread count |

### Model

| Variable | Default | Description |
|----------|---------|-------------|
| `ACESTEP_CONFIG_PATH` | `acestep-v15-turbo` | Primary DiT model |
| `ACESTEP_DEVICE` | `auto` | Device for model loading |
| `ACESTEP_INIT_LLM` | `auto` | Initialize LM at startup |
| `ACESTEP_LM_MODEL_PATH` | `acestep-5Hz-lm-0.6B` | 5Hz LM model |
| `ACESTEP_LM_BACKEND` | `vllm` | LM backend (vllm or pt) |

### Queue

| Variable | Default | Description |
|----------|---------|-------------|
| `ACESTEP_QUEUE_MAXSIZE` | `200` | Maximum queue size |
| `ACESTEP_QUEUE_WORKERS` | `1` | Number of queue workers |

---

## Error Handling

| HTTP Status | Description |
|-------------|-------------|
| `200` | Success |
| `400` | Invalid request |
| `401` | Unauthorized |
| `404` | Not found |
| `429` | Server busy (queue full) |
| `500` | Internal server error |

---

## Best Practices

1. **Use `thinking=true`** for best quality results
2. **Use `sample_query`** for quick generation from descriptions
3. **Use `use_format=true`** when you want LM to enhance your caption/lyrics
4. **Batch query** multiple tasks at once with `/query_result`
5. **Check `/v1/stats`** to understand server load
6. **Set `ACESTEP_API_KEY`** for production use

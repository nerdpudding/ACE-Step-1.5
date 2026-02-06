# ACE-Step Music Creation Guide

> This guide contains professional music creation knowledge for ACE-Step. Use this as reference when creating music — whether you're an AI assistant, a human, or an automated pipeline.

---

## Input Control: What Do You Want?

This is where you communicate "creative intent" with the model — what kind of music to generate.

| Category | Parameter | Function |
|----------|-----------|----------|
| **Text Input** | `prompt` / `caption` | Description of overall music elements: style, instruments, emotion, atmosphere, timbre, vocal gender, progression, etc. |
| | `lyrics` | Temporal element description: lyric content, music structure evolution, vocal changes, start/end style, articulation, etc. (use `[Instrumental]` for instrumental music) |
| **Music Metadata** | `bpm` | Tempo (30-300) |
| | `key_scale` | Key (e.g., C Major, Am) |
| | `time_signature` | Time signature (4/4, 3/4, 6/8) |
| | `language` | Vocal language |
| | `duration` | Target duration (seconds) |
| **Audio Reference** | `src_audio_path` | Source audio for continuation/repainting tasks |
| **Task Type** | `task_type` | text2music, cover, repaint, continuation |

---

## About Caption: The Most Important Input

**Caption is the most important factor affecting generated music.**

It supports multiple input formats: simple style words, comma-separated tags, complex natural language descriptions. The model is trained to handle various formats.

### Common Dimensions for Caption Writing

| Dimension | Examples |
|-----------|----------|
| **Style/Genre** | pop, rock, jazz, electronic, hip-hop, R&B, folk, classical, lo-fi, synthwave |
| **Emotion/Atmosphere** | melancholic, uplifting, energetic, dreamy, dark, nostalgic, euphoric, intimate |
| **Instruments** | acoustic guitar, piano, synth pads, 808 drums, strings, brass, electric bass |
| **Timbre Texture** | warm, bright, crisp, muddy, airy, punchy, lush, raw, polished |
| **Era Reference** | 80s synth-pop, 90s grunge, 2010s EDM, vintage soul, modern trap |
| **Production Style** | lo-fi, high-fidelity, live recording, studio-polished, bedroom pop |
| **Vocal Characteristics** | female vocal, male vocal, breathy, powerful, falsetto, raspy, choir |
| **Speed/Rhythm** | slow tempo, mid-tempo, fast-paced, groovy, driving, laid-back |
| **Structure Hints** | building intro, catchy chorus, dramatic bridge, fade-out ending |

### Practical Principles for Caption Writing

1. **Specific beats vague** — "sad piano ballad with female breathy vocal" works better than "a sad song."

2. **Combine multiple dimensions** — Single-dimension descriptions give the model too much freedom; combining style+emotion+instruments+timbre anchors the direction more precisely.

3. **Use references well** — "in the style of 80s synthwave" or "reminiscent of Bon Iver" can quickly convey complex aesthetic preferences.

4. **Texture words are useful** — Adjectives like warm, crisp, airy, punchy influence mixing and timbre tendencies.

5. **Don't pursue perfect descriptions** — Caption is a starting point, not an endpoint. Write a general direction first, then iterate based on results.

6. **Description granularity determines freedom** — More omitted descriptions give the model more room to play. More detailed descriptions constrain the model. Want surprises? Write less. Want control? Write more.

7. **Avoid conflicting words** — Conflicting style combinations lead to degraded output. For example, "classical strings" and "hardcore metal" simultaneously.

   **Ways to resolve conflicts:**
   - **Repetition reinforcement** — Strengthen the elements you want more by repeating certain words
   - **Conflict to evolution** — Transform style conflicts into temporal evolution. For example: "Start with soft strings, middle becomes noisy dynamic metal rock, end turns to hip-hop"

---

## About Lyrics: The Temporal Script

If Caption describes the music's "overall portrait" — style, atmosphere, timbre — then **Lyrics is the music's "temporal script"**, controlling how music unfolds over time.

Lyrics carry more than just text:
- The lyric text itself
- **Structure tags** ([Verse], [Chorus], [Bridge]...)
- **Vocal style hints** ([raspy vocal], [whispered]...)
- **Instrumental sections** ([guitar solo], [drum break]...)
- **Energy changes** ([building energy], [explosive drop]...)

### Common Structure Tags

| Category | Tag | Description |
|----------|-----|-------------|
| **Basic Structure** | `[Intro]` | Opening, establish atmosphere |
| | `[Verse]` / `[Verse 1]` | Verse, narrative progression |
| | `[Pre-Chorus]` | Pre-chorus, build energy |
| | `[Chorus]` | Chorus, emotional climax |
| | `[Bridge]` | Bridge, transition or elevation |
| | `[Outro]` | Ending, conclusion |
| **Dynamic Sections** | `[Build]` | Energy gradually rising |
| | `[Drop]` | Electronic music energy release |
| | `[Breakdown]` | Reduced instrumentation, space |
| **Instrumental Sections** | `[Instrumental]` | Pure instrumental, no vocals |
| | `[Guitar Solo]` | Guitar solo |
| | `[Piano Interlude]` | Piano interlude |
| **Special Tags** | `[Fade Out]` | Fade out ending |
| | `[Silence]` | Silence |

### Combining Tags: Use Moderately

Structure tags can be combined with `-` for finer control:

```
[Chorus - anthemic]
This is the chorus lyrics
Dreams are burning

[Bridge - whispered]
Whisper those words softly
```

**Don't stack too many tags:**

```
Not recommended:
[Chorus - anthemic - stacked harmonies - high energy - powerful - epic]

Recommended:
[Chorus - anthemic]
```

**Principle**: Keep structure tags concise; put complex style descriptions in Caption.

### Maintain Consistency Between Caption and Lyrics

**Models are not good at resolving conflicts.** If descriptions in Caption and Lyrics contradict, the model gets confused and output quality decreases.

**Checklist:**
- Instruments in Caption should match instrumental section tags in Lyrics
- Emotion in Caption should match energy tags in Lyrics
- Vocal description in Caption should match vocal control tags in Lyrics

Think of Caption as "overall setting" and Lyrics as "shot script" — they should tell the same story.

### Vocal Control Tags

| Tag | Effect |
|-----|--------|
| `[raspy vocal]` | Raspy, textured vocals |
| `[whispered]` | Whispered |
| `[falsetto]` | Falsetto |
| `[powerful belting]` | Powerful, high-pitched singing |
| `[spoken word]` | Rap/recitation |
| `[harmonies]` | Layered harmonies |
| `[call and response]` | Call and response |
| `[ad-lib]` | Improvised embellishments |

### Energy and Emotion Tags

| Tag | Effect |
|-----|--------|
| `[high energy]` | High energy, passionate |
| `[low energy]` | Low energy, restrained |
| `[building energy]` | Increasing energy |
| `[explosive]` | Explosive energy |
| `[melancholic]` | Melancholic |
| `[euphoric]` | Euphoric |
| `[dreamy]` | Dreamy |
| `[aggressive]` | Aggressive |

### Lyric Text Writing Tips

**1. Control Syllable Count**

**6-10 syllables per line** usually works best. The model aligns syllables to beats — if one line has 6 syllables and the next has 14, rhythm becomes strange.

**Tip**: Keep similar syllable counts for lines in the same position (e.g., first line of each verse).

**2. Use Case to Control Intensity**

Uppercase indicates stronger vocal intensity:

```
[Verse]
walking through the empty streets (normal intensity)

[Chorus]
WE ARE THE CHAMPIONS! (high intensity, shouting)
```

**3. Use Parentheses for Background Vocals**

```
[Chorus]
We rise together (together)
Into the light (into the light)
```

Content in parentheses is processed as background vocals or harmonies.

**4. Extend Vowels**

You can extend sounds by repeating vowels:

```
Feeeling so aliiive
```

Use cautiously — effects are unstable, sometimes ignored or mispronounced.

**5. Clear Section Separation**

Separate each section with blank lines:

```
[Verse 1]
First verse lyrics
Continue first verse

[Chorus]
Chorus lyrics
Chorus continues
```

### Avoiding "AI-flavored" Lyrics

| Red Flag | Description |
|----------|-------------|
| **Adjective stacking** | "neon skies, electric hearts, endless dreams" — filling a section with vague imagery |
| **Rhyme chaos** | Inconsistent rhyme patterns, or forced rhymes causing semantic breaks |
| **Blurred section boundaries** | Lyric content crosses structure tags, Verse content "flows" into Chorus |
| **No breathing room** | Each line too long, can't sing in one breath |
| **Mixed metaphors** | First verse uses water imagery, second suddenly becomes fire, third is flying |

**Metaphor discipline**: Stick to one core metaphor per song, exploring its multiple aspects.

---

## About Music Metadata: Optional Fine Control

**Most of the time, you don't need to manually set metadata.**

When you enable `thinking` mode, the LM automatically infers appropriate BPM, key, time signature, etc. based on your Caption and Lyrics. This is usually good enough.

But if you have clear ideas, you can manually control them:

| Parameter | Range | Description |
|-----------|-------|-------------|
| `bpm` | 30-300 | Tempo. Slow songs 60-80, mid-tempo 90-120, fast songs 130-180 |
| `key_scale` | Key | e.g., `C Major`, `Am`, `F# Minor`. Affects pitch and emotional color |
| `time_signature` | Time sig | `4/4` (most common), `3/4` (waltz), `6/8` (swing feel) |
| `language` | Language | Vocal language. LM usually auto-detects from lyrics |
| `duration` | Seconds | Target duration. Actual generation may vary slightly |

### Understanding Control Boundaries

These parameters are **guidance** rather than **precise commands**:

- **BPM**: Common range (60-180) works well; extreme values have less training data
- **Key**: Common keys (C, G, D, Am, Em) are stable; rare keys may be shifted
- **Time signature**: `4/4` is most reliable; `3/4`, `6/8` usually OK; complex signatures vary by style
- **Duration**: Short songs (30-60s) and medium length (2-4min) are stable; very long generation may have repetition issues

### When Do You Need Manual Settings?

| Scenario | Suggestion |
|----------|------------|
| Daily generation | Don't worry, let LM auto-infer |
| Clear tempo requirement | Manually set `bpm` |
| Specific style (e.g., waltz) | Manually set `time_signature=3/4` |
| Need to match other material | Manually set `bpm` and `duration` |
| Pursue specific key color | Manually set `key_scale` |

**Tip**: Don't write tempo, BPM, key info in Caption. Use dedicated metadata parameters instead. Caption should focus on style, emotion, instruments, and timbre.

---

## Duration Calculation Guidelines

When creating music, calculate appropriate duration based on lyrics content and song structure:

### Estimation Method

- **Per line of lyrics**: 3-5 seconds
- **Intro/Outro**: 5-10 seconds each
- **Instrumental sections**: 5-15 seconds each
- **Typical song structures**:
  - 2 verses + 2 choruses: 120-150 seconds minimum
  - 2 verses + 2 choruses + bridge: 180-240 seconds minimum
  - Full song with intro/outro: 210-270 seconds (3.5-4.5 minutes)

### Common Pitfalls

- **DON'T** set duration too short for the lyrics amount (10 lines with 60 seconds = rushed)
- **DO** calculate realistic duration (10 lines = ~40s vocals + 20s intro/outro = 60s minimum)

### BPM and Duration Relationship

- **Slower BPM (60-80)**: Need MORE duration for same lyrics
- **Medium BPM (100-130)**: Standard duration
- **Faster BPM (150-180)**: Can fit more lyrics in less time, but still need breathing room

**Rule of thumb**: When in doubt, estimate longer rather than shorter. A song that's too short will feel rushed.

---

## Complete Example

**Caption**: `female vocal, piano ballad, emotional, intimate atmosphere, strings, building to powerful chorus`

**Lyrics**:
```
[Intro - piano]

[Verse 1]
Moonlight falls upon the window
I can hear you breathing slow
The city sleeps in distant silence
Only we remain aglow

[Pre-Chorus - building energy]
This moment hangs so still
Yet hides a rushing heart

[Chorus - powerful]
Let us burn together
Like fireworks across the sky
Brief but blazing brightly
This is our moment, you and I

[Verse 2]
Time is slipping through our fingers
Nothing we can hold for long
But at least right now we're burning
With a fire that makes us strong

[Bridge - whispered]
If tomorrow takes it all away
At least we shone today

[Final Chorus - explosive]
LET US BURN TOGETHER
LIKE FIREWORKS ACROSS THE SKY
BRIEF BUT BLAZING BRIGHTLY
THIS IS OUR MOMENT, YOU AND I

[Outro - fade out]
```

**Parameters**: `duration: 210, bpm: 72, key_scale: "A Minor", time_signature: "4", language: "en"`

Note: Lyrics tags (piano, powerful, whispered, explosive) are consistent with Caption descriptions (piano ballad, building to powerful chorus, intimate). No conflicts.

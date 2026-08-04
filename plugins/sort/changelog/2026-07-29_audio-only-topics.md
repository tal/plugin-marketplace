# sort-videos: audio-only topics — comedy gets an MP3, not a transcript

## What changed

`/sort-videos` now recognizes an **audio-only topic set**, defaulting to `Comedy`. A video that lands in one of those topics is exported as a tagged MP3 and nothing else — no whisper transcription, no OCR, no oEmbed enrichment, no talk/lecture detection, and **no companion `.md` summary**.

The motivation: a transcript of a standup special is worthless, because the timing *is* the act, and a written summary of jokes actively destroys them. What you actually want off a comedy special is the audio on your phone. The old pipeline did the opposite — a 42-minute special tripped every `talk-or-lecture` signal (long, single speaker, audience laughter and applause) and earned itself a TL;DR, an outline, and a Key Points section.

The video file is **kept**: it is renamed and moved as usual, and the MP3 lands beside it. Nothing is deleted.

## New: §0.6 Audio-only topics

Defines the set, the per-step skip table, and — the part that needed actual design — **how to decide before transcribing**. Normal categorization (§5) reads the transcript, but an audio-only video never gets one, so it's a chicken-and-egg problem. The resolution:

1. Pre-classify from the filename, title, and creator alone. yt-dlp names carry plenty of signal: `(Full Comedy Special)`, `(Full Special)`, `Stand-Up`, `Live at the Apollo`, comedy channel and club names.
2. Confident hit on an audio-only topic → jump straight to §6 → §7 → §8. No WAV conversion, no whisper.
3. A §0.5 `route` rule pinning the video to an audio-only folder counts as a confident pre-classification.
4. Ambiguous filename → fall through to the normal flow, transcribe, categorize in §5, and if the topic *then* turns out to be audio-only, still honor it: export the MP3, skip the `.md`, discard the transcript. A wasted transcription is acceptable; a wrong topic is not.
5. Only ask the user when the filename is genuinely uninformative — `(Full Comedy Special)` is not.

Configurable via the top-level frontmatter key `audio_only_topics` in any of the §0.5 override files. Unlike `paprika_sidecar`, this key has a **non-empty default** (`[Comedy]`), so opting *out* is the explicit action: `audio_only_topics: []`.

## Step-by-step gates

- **§1 Transcribe** — skipped outright for audio-only; no WAV, no whisper.
- **§2 OCR** — skipped, and the AskUserQuestion prompt is suppressed. There's no `.md` for extracted text to land in, so asking would be dead weight.
- **§3 Enrich** — caption fetch skipped. Filename parsing for platform/creator/ID still happens, since §6 and §7 need it.
- **§4 Talk detection** — skipped; the classification only picks a markdown body format. Type is `audio-only`.
- **§5 Categorize** — the §0.6 pre-classification is the topic, but folder discovery still runs so the existing spelling on disk wins (`Comedy`, not a freshly invented `Stand-Up`).
- **§6 Rename/move** — renames and moves as usual, but the `<brief-description>` slug comes from the **title** rather than the content, since there's no transcript to derive it from: `youtube - Emily Catalano ｜ The Introvert (Full Comedy Special) [bt_I3nJmQ3I].webm` → `the-introvert - Youtube - Emily Catalano [bt_I3nJmQ3I].webm`. No `.md` is written and §6.5 is skipped. A pre-existing `.md` from an earlier transcribing run is **left in place** — deleting notes the user may value isn't this skill's call — and reported in §10.
- **§7 Audio export** — generalized from "talks and lectures" to also cover audio-only topics. For a talk the MP3 accompanies the summary, so an ffmpeg failure is survivable; for an audio-only topic the MP3 *is* the only output, so a failure is hard and gets logged as `skipped`. Tag sourcing documented per case, including `genre` = the topic name (`Comedy`) and `comment` **omitted**, since manufacturing a one-liner would mean watching the thing.
- **§8 Processing log** — new `audio-only` Type. The `Summary` states only what's honestly known without a transcript: title and performer, plus "audio exported, not transcribed."
- **§9 Parallelism** — audio-only MP3 exports start immediately, in parallel with other videos' transcriptions; they have no WAV stage to wait on.
- **§10 Report** — `Outputs` gains `mp3` (no `md` **by design**, stated in the row so it doesn't read as a failure), and a line under the table names the rule that fired and how to disable it. A user who forgot they configured this shouldn't have to wonder why their special has no notes.

## Files touched

- `plugins/sort/skills/sort-videos/SKILL.md` — new §0.6; gates and cross-references added to §0.5 and §§1–10; §7 retitled and generalized from talks-only to all audio exports.
- `plugins/sort/skills/sort/OVERRIDES.md` — `audio_only_topics` documented in the top-level keys table.
- `plugins/sort/README.md` — `/sort-videos` row mentions audio-only topics.

## Not done

- `paprika_sidecar` is still undocumented in `OVERRIDES.md`'s top-level keys table (it's only described in `sort-videos` SKILL.md §0.5/§6.5). Pre-existing gap, left alone to keep this change scoped.

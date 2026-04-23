# Detect talks and lectures with extended summaries

Added a new classification step to the `sort-videos` skill that flags videos as either `short-form` or `talk-or-lecture` based on both length and content, then writes a more extensive summary for talks.

## Changes

- **New step 4: Detect talks and lectures** — uses `ffprobe` for duration and the transcription content for lecture/talk patterns (sustained monologue, clear structure, academic register, Q&A, audience reactions). Videos under 5 minutes skip classification; videos 5-15 minutes use the content signal; videos over 15 minutes default to talk unless content disagrees.
- **AskUserQuestion fallback** — when the length and content signals disagree or are weak, the skill asks the user to pick `short-form` or `talk-or-lecture`. It does NOT ask when the classification is obvious.
- **Extended markdown format for talks/lectures** — replaces the raw-transcript dump with structured sections: `TL;DR`, `Outline`, `Key Points`, `Notable Quotes`, `Terms & Concepts`, `References`, `Q&A Highlights`, `Takeaways`. Short-form videos keep the original format.
- **Categorization preference** — talks/lectures prefer `Education` or a subject-specific folder (`Tech`, `Self-Improvement`), falling back to a new `Talks & Lectures` folder only when no existing subject fits.
- **Tagged MP3 export for talks/lectures (new step 7)** — after writing the markdown, talks/lectures also get an MP3 alongside the video so they can be listened to on a phone or podcast app. Uses ffmpeg with libmp3lame at 128 kbps and populates ID3v2 tags (`title`, `artist` / `album_artist` = speaker, `album` = conference/series/platform, `genre` = `Speech`, `date`, `comment` = TL;DR). Falls back to creator/platform metadata from the filename when speaker/series aren't known. Short-form videos skip this step.
- **Report table** — added a `Type` column so the final summary distinguishes short-form from talk/lecture videos, and an `Outputs` column showing `md` or `md + mp3`.
- **Skill description** — updated to mention talk/lecture handling, tagged MP3 export, and the "summarize a talk or lecture video" invocation phrasing.

Steps 4-7 were renumbered to accommodate two new steps (detection at 4, audio export at 7); the final step count is now 9.

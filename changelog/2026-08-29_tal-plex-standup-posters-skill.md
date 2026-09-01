# Tal Plex stand-up posters skill

Added the auto-discovered `plex-standup-posters` skill to the `tal` plugin.

The skill captures the complete personal Standup-library workflow:

- inventory new YouTube-style files and provider-managed folders without matching poster sidecars or `movie.nfo` metadata;
- resolve exact comedian and special titles before choosing artwork;
- prefer inspected official portrait art and generate only the missing designs;
- normalize and visually check `1000x1500` posters;
- scan only the Plex `Standup` section;
- install exact-basename sidecars and directly select uploaded Plex posters;
- verify the sidecar, selected upload key, and image served back by Plex.
- add the performer as an actor in Plex's `Role` collection and verify the cast tag.

Documented that legacy-agent cast tags are text-only unless Plex returns a canonical person `tagKey`/`thumb`, and that canonical linking requires an explicit provider migration or separately approved database migration.

The skill also documents durable `movie.nfo` metadata for provider-managed releases such as Netflix specials, including the Plex metadata API fallback required by the legacy YouTube agent.

It includes `scripts/plex-standup-posters.sh` with `inventory`, `scan`, `install`, and `verify` commands. The helper uses guarded personal defaults for `synfeld`, `/volume1/Media/Standup`, and the local Plex credentials file, with environment overrides for each setting.

Updated the Tal plugin manifests and both README inventories to include the new media workflow.

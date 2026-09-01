# Example manifests

Each file is a complete, valid `.library.yml` for one shape (copy the body, save it as `.library.yml` inside
the folder). The first line is the editor hint; swap the host for `http://localhost:8420` in dev. Passwords
here are placeholders — real ones must be throwaway, unique per folder, quoted if numeric or containing
` #` or `: `.

| File | Shape |
|---|---|
| `titled-collection.yml` | public, listed, custom title |
| `protected.yml` | password-gated, still listed with a lock |
| `protected-unlisted.yml` | link-only **and** password-gated |
| `rekeyed-child.yml` | second key for a sub-folder of a protected parent |
| `hidden.yml` | never scanned |
| `unlisted.yml` | public, link-only |
| `protected-root.yml` | whole library behind one password (goes in the library root) |
| `app-entry-only.yml` | static app, no build |
| `app-with-build.yml` | static app with a `Bun.build` entry (needs `TRUSTED_APPS`) |
| `preview-file.yml` | card picture from a file in the folder |
| `preview-none.yml` | force the glyph even though the folder has a Finder icon |
| `does-not-work.yml` | the shapes people try that the narrow-only rule ignores, with the warning each produces |

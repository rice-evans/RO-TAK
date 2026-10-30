# RO-TAK

Annotate a game map with your team in real time. Upload a map, draw, drop military symbols and waypoints, and share a room link.

- Web: https://ro-tak.vercel.app
- Desktop overlay (Windows, macOS): see Releases

## What it does and does not do

- Runs on its own. It does not read, inject into or modify any game.
- No accounts and no analytics.
- Rooms sync through Supabase and are deleted after 2 hours with nobody connected.
- Uploaded maps are checked with OpenAI's moderation endpoint before they are stored.

## Layout

- `index.html` - the whole app. The website and the Electron overlay load the same file.
- `desktop/` - Electron wrapper.
- `supabase/` - SQL and the `upload-map` edge function.
- `.github/` - builds the installers on GitHub Actions from this source.

## Run your own copy

1. Create a Supabase project and run `supabase/moderation.sql`, then `supabase/host.sql`.
2. Create a public storage bucket named `maps`.
3. Deploy `supabase/functions/upload-map` with JWT verification off and an `OPENAI_API_KEY` secret.
4. Put your project URL and publishable key in `index.html` (`SUPABASE_URL`, `SUPABASE_KEY`).
5. Host the folder on any static host. `vercel.json` rewrites `/play` to `index.html`.

## Verify a download

Installers are built by GitHub Actions from this repo and carry a signed build attestation.

```
gh attestation verify RO-TAK-Setup-x.y.z.exe --repo rice-evans/RO-TAK
```

Each release also has `SHA256SUMS-Windows.txt` and `SHA256SUMS-macOS.txt`. Compare with `Get-FileHash <file>` on Windows or `shasum -a 256 <file>` on macOS.

## License

MIT, see `LICENSE`. The landing page photos belong to their credited owners and are not covered by it.
Third party: milsymbol (MIT), supabase-js (MIT), IBM Plex Sans (SIL OFL).

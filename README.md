# Arolel

A small suite of everyday web utilities. Nine tools under one roof. Most of them run entirely in your browser — your files never leave your device.

Built on Rails 8 + Stimulus + Tailwind. No ads, no trackers, no email walls. Accounts are optional; the tools work signed-out.

## The tools

| # | Tool | URL | Where it runs |
|---|---|---|---|
| 01 | HEIC → JPG / PNG / WebP | `/heic-to-jpg` | Browser (`heic2any`) |
| 02 | PDF merge / split / rotate / compress | `/pdf/:op` | Browser (`pdf-lib`) |
| 03 | Is It Down? — shareable uptime boards | `/down`, `/down/b/:slug` | Server |
| 04 | Bulk URL opener + saveable sets | `/open`, `/o/:slug` | Server |
| 05 | Image compress (JPG / PNG / WebP) | `/images/compress` | Browser (`canvas.toBlob`) |
| 06 | Invoice maker — 3 templates | `/invoice` | Browser (`pdf-lib`) |
| 07 | Sign PDF — draw, type, or upload | `/sign` | Browser (`pdf-lib`) |
| 08 | MP4 → MP3 audio extract | `/media/mp4-to-mp3` | Browser (`ffmpeg.wasm`) |
| 09 | WebM → MP4 | `/media/webm-to-mp4` | Browser (`ffmpeg.wasm`) |

Each in-browser tool shows a live "0 bytes sent" receipt that reads the browser's own `performance.getEntriesByType('resource')` API — so the privacy claim is verifiable, not just promised.

## Stack

- Rails 8.1 · Ruby 3.4
- PostgreSQL · Solid Queue · Solid Cache · Solid Cable
- Stimulus · Turbo · Propshaft
- `jsbundling-rails` (esbuild) · `cssbundling-rails` (Tailwind 4)
- Auth: `has_secure_password` + Rails 8 built-in authentication

## Development

```sh
# Dependencies
bundle install
yarn install
bin/fetch_ffmpeg

# Database
bin/rails db:create db:migrate

# Dev server (Puma + asset watchers)
bin/dev
# → http://localhost:7000
```

## Production

Deployed via Hatchbox. App reads:

| Env var | Purpose |
|---|---|
| `APP_HOST` | Comma-separated allowlist for Rails host auth (e.g. `arolel.com,www.arolel.com`) |
| `PUBLIC_HOST` | Canonical public host used in share previews and generated links (default: `arolel.com`) |
| `PUBLIC_URL` | Canonical public URL including protocol (default: `https://arolel.com`) |
| `MAIL_DOMAIN` | Domain used for the default `no-reply` sender (defaults to `PUBLIC_HOST` / first `APP_HOST`) |
| `COFFEE_URL` | Optional Buy Me A Coffee link — if unset, the button is hidden |
| `SOURCE_URL` | Optional public source-code link — if unset, hidden from the footer |
| `SECRET_KEY_BASE` | Standard Rails secret |
| `DATABASE_URL` | Standard Rails PG URL |

`config.assume_ssl = true` and `config.force_ssl = true` are on in production.

## Design

Chalk-neutral palette (`#f6f5f1` page, `#ffffff` paper, `#14161a` ink) with Arolel moss (`#2f6f4e`) as the signal colour. The primary mark is the Bundle logo in `app/assets/images/logo/`. Type pairing: **Instrument Serif** for the wordmark, **Source Serif 4** for H1s, **Inter** for UI, and **JetBrains Mono** for numbers, URLs, and receipts. Design tokens live in `app/assets/stylesheets/application.tailwind.css`.

## License

MIT — see source tree.

# Contributing to Arolel

Thanks for wanting to contribute. Arolel is intended to stay privacy-first, practical, and easy to self-host.

## Project Direction

Arolel is a toolkit of everyday browser utilities. File tools should run locally in the browser whenever practical, so private files do not leave the user's device.

Good contributions include:

- Bug fixes
- Accessibility improvements
- Browser compatibility fixes
- Focused UI polish
- Tests and documentation
- New utilities that fit the privacy-first direction
- Performance improvements for client-side file processing

Please open an issue before:

- Large rewrites
- New dependencies with broad impact
- Server-side file upload/storage features
- Marketing, analytics, or tracking features
- Major UI direction changes

## Development

```sh
bundle install
yarn install
bin/fetch_ffmpeg
bin/rails db:create db:migrate
bin/dev
```

The app runs at `http://localhost:7000` by default.

## Checks

Run these before opening a pull request:

```sh
bin/rails test
RUBOCOP_CACHE_ROOT=/tmp/rubocop_cache bin/rubocop
```

If your change touches JavaScript or CSS, also make sure assets build:

```sh
yarn build
```

## Pull Requests

- Keep PRs small and focused.
- Explain the user-facing behavior change.
- Include screenshots for UI changes.
- Add tests when changing server-side behavior.
- Do not commit secrets, credentials, real SMTP keys, database dumps, or production `.env` files.

## Privacy Rules

- Do not add third-party analytics or tracking scripts.
- Do not upload private user files to the server unless the feature has been discussed first.
- Do not add external CDN scripts for core file processing.
- Keep the "0 bytes sent" privacy claim accurate for browser-only tools.

## Maintainer

Maintained by Oluwadare Juwon.

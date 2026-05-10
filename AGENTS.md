# AGENTS.md — ttop

## Build

- **Release (dynamic):** `nimble -d:release build`
- **Static release (primary artifact, requires `musl-tools`/`musl-gcc`):** `nimble static`
- **Static debug (requires `musl-tools`):** `nimble staticdebug`
- **Benchmark:** `nimble bench` (uses `criterion` library; bench sources in `bench/`)

There is no test suite.

## Architecture

- **Entry point:** `src/ttop.nim` → calls `tui()` from `src/ttop/tui.nim`
- **All source** lives under `src/ttop/`:
  - `tui.nim` — TUI rendering and key handling
  - `procfs.nim` — /proc parsing, process info, data types (`FullInfoRef`, `PidInfo`, `SortField`, etc.)
  - `blog.nim` — historical snapshot storage (gzip-compressed JSON)
  - `config.nim` — TOML config loading (`~/.config/ttop/ttop.toml` or `/etc/ttop.toml`)
  - `limits.nim` — threshold constants for alerts (CPU 80%, mem 80%, swap 50%, etc.)
  - `format.nim` — human-readable number/time formatters
  - `triggers.nim` — external trigger execution on alerts
  - `onoff.nim` — systemd.timer / crontab collector enable/disable
  - `sys.nim` — POSIX bindings (`statvfs`, `sysconf`)
- Config: `ttop.nimble` (srcDir=src, bin=ttop, version line 3)

## Dependencies (forks)

Two dependencies are forks — install with `nimble -y -d install` (not plain `nimble install`):
- `https://github.com/inv2004/illwill` (TUI library fork)
- `https://github.com/inv2004/jsony#non_quoted_key` (JSON fork with non-quoted keys)

Other deps: `zippy`, `asciigraph`, `parsetoml`. Requires Nim >= 2.0.10.

## Notes

- Static builds pass `NimblePkgVersion` define manually via `-d:NimblePkgVersion=<version>` matching `ttop.nimble` version
- `bench/config.nims` adds `../src` to the import path for bench files
- Build output (`ttop`, `ttop-debug`) is in `.gitignore`
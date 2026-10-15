# Changelog

## v1.0.0 — 2026-10-15 (preview)

- Add F5 and Ctrl+Alt+R page-reload shortcuts, registered only while the game is focused.
- Add a one-shot renderer recreation fallback after an 8-second stalled reload, or when Electron reports an unresponsive window.
- Record recovery actions, renderer exits and process memory statistics locally.
- Include a PowerShell installer, read-only status checker and hash-verified uninstall.
- Preserve the pre-install archive, existing translations, HoldKeys and game save data.
- Include dependency-free runtime tests and optional archive comparison tests.

Normal reload has been verified on a real Steam Windows 11.5 installation. Recovery from a genuine white-screen incident has not yet been verified; the root cause remains unresolved.

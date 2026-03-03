# HugoDesk

HugoDesk is a native macOS client (SwiftUI) for Hugo blog writing, configuration, and publishing.

## Run

```bash
cd /Users/sexyfeifan/Library/Mobile\ Documents/com~apple~CloudDocs/Code/HugoDesk
swift run
```

## Highlights

- Markdown writing with preview toggle and right-click/selection tools
- New post workflow with filename-from-title generation and metadata helpers
- Theme settings editor for `github-style`
- Image import and auto image-link normalization before publish
- Git build/status/publish workflow and GitHub Actions status check
- AI formatting workflow (configurable API endpoint/model/key)
- Release diagnostics with non-fast-forward detection and sync guidance

## What's New ✨ (v0.3.7)

- 🧭 Persisted last selected blog root path to avoid running commands in the wrong directory after app restart
- 🧰 Expanded context-menu and selection markdown tools (H1-H6, table, details, footnote, divider)
- 🖼️ Improved preview local-image resolution for `images/...`, `static/...`, and `./images/...`
- 📦 Publish console now saves project config bundle directly instead of writing unrelated theme settings
- 🔐 Publish/sync/diagnostics now support GitHub token authentication without exposing token in logs

## Artifact Layout

- Current version only: `latest/`
- Historical versions: `HugoDeskArchive/versions/<version>/`

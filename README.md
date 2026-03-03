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

## What's New ✨ (v0.3.5)

- 🚫 Added `hugo.toml` to publish exclusion rules to prevent accidental upload
- 🧱 Improved `git add` fallback for ignored `.hugodesk.local.json` pathspec failures
- 🗂️ Kept full error details in publish logs while status bar now shows concise messages only
- 🧼 Reduced visual noise in bottom status area with single-line truncation

## Artifact Layout

- Current version only: `latest/`
- Historical versions: `HugoDeskArchive/versions/<version>/`

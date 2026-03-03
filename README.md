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

## What's New ✨ (v0.3.4)

- 📜 Reworked publish output into structured logs (command, cwd, exit code, duration, stdout, stderr)
- 🧠 Added automatic AI troubleshooting suggestions on publish failures (when AI config is present)
- 🗂️ Added foldable log panel with clear/copy actions and selectable text
- ✍️ Fixed Chinese Pinyin IME interruption in markdown editor by skipping sync during marked text composition
- 🧱 Kept blog-publish guardrails to exclude HugoDesk/HugoDeskArchive/.hugodesk.local.json

## Artifact Layout

- Current version only: `latest/`
- Historical versions: `HugoDeskArchive/versions/<version>/`

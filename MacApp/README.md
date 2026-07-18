# LocalAgent (macOS SwiftUI)

Native Mac client for [local-agent](../). Talks to the existing Python FastAPI backend over `http://127.0.0.1:8501`.

## Requirements

- macOS 14+
- Xcode 15+
- Python 3.11+ with `local-agent` deps (`pip install -r ../requirements.txt`)
- `application/config.json` configured (see repo README)

## Generate & open

```bash
cd MacApp
xcodegen generate
open LocalAgent.xcodeproj
```

Then **Product → Run** (⌘R).

CLI compile check (no full Xcode app required if Swift toolchain is present):

```bash
cd MacApp
swift build
```

## Behavior

1. App checks `/api/health`
2. If down, spawns `scripts/run_api.sh` (uvicorn only)
3. Sets session cookie via `/api/session`
4. Task list / chat SSE / Skill·MCP·Model settings / image upload

App Sandbox is **off** so the process can start Python and read the repo.

## Settings

**Local Agent → Settings…**

- User ID
- Repo root override
- Python path override
- Restart server

#!/usr/bin/env bash
# Start FastAPI only (no frontend build). Used by the Swift Mac app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8501}"
HOST="${HOST:-127.0.0.1}"

cd "$ROOT"

pick_python() {
  if [[ -n "${PYTHON:-}" && -x "${PYTHON}" ]]; then
    echo "${PYTHON}"
    return
  fi
  candidates=(
    "$ROOT/.venv/bin/python3"
    "$ROOT/../agent-skills/.venv/bin/python3"
  )
  for py in "${candidates[@]}"; do
    if [[ -x "$py" ]] && "$py" -c "import uvicorn" 2>/dev/null; then
      echo "$py"
      return
    fi
  done
  if command -v python3 >/dev/null && python3 -c "import uvicorn" 2>/dev/null; then
    command -v python3
    return
  fi
  echo "error: no python with uvicorn found. Create .venv and pip install -r requirements.txt" >&2
  exit 1
}

PYTHON_BIN="$(pick_python)"
echo "==> local-agent API on ${HOST}:${PORT}"
echo "    python: ${PYTHON_BIN}"
echo "    root:   ${ROOT}"

# Free port if occupied (macOS)
if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${PIDS}" ]]; then
    echo "    Port ${PORT} in use by PID(s): ${PIDS} — killing"
    # shellcheck disable=SC2086
    kill ${PIDS} 2>/dev/null || true
    sleep 1
  fi
fi

export PYTHONUNBUFFERED=1
exec "${PYTHON_BIN}" -m uvicorn application.server:app --host "${HOST}" --port "${PORT}"

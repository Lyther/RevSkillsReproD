#!/usr/bin/env bash
#
# live-skill.sh — ByteLLM smoke: apply re-analyze Level 0 to a pasted C snippet.
# Authorized evaluation of our own snippet. Never prints keys.
#
# Usage: live-skill.sh
#
# Env:
#   BYTELLM_BASE_URL   default http://127.0.0.1:4000/v1
#   BYTELLM_KEY_FILE   default ~/.ssh/bytellm (client). Do not use ByteLLM/.env.
#   BYTELLM_KEY_LINE   default 11
#   BYTELLM_MODEL      default qwen3-max (ByteLLM/.env key-11 pool)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/bytellm-key.sh"

BYTELLM_BASE_URL="${BYTELLM_BASE_URL:-http://127.0.0.1:4000/v1}"
BYTELLM_KEY_LINE="${BYTELLM_KEY_LINE:-11}"
BYTELLM_MODEL="${BYTELLM_MODEL:-qwen3-max}"
BYTELLM_KEY_FILE="$(bytellm_default_key_file)"
readonly MARKER="REVSKILLS_REPRO_OK"

log() { printf '%s [%s] %s\n' "$(date -Iseconds)" "${SCRIPT_NAME}" "$*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}

cleanup() {
    local exit_code=$?
    [[ -n "${HEADER:-}" ]] && rm -f -- "${HEADER}"
    [[ -n "${BODY:-}" ]] && rm -f -- "${BODY}"
    [[ -n "${REQ:-}" ]] && rm -f -- "${REQ}"
    exit "${exit_code}"
}
trap cleanup EXIT

main() {
    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v python3 >/dev/null 2>&1 || die "python3 is required"
    [[ -f "${BYTELLM_KEY_FILE}" ]] || die "missing ${BYTELLM_KEY_FILE}"
    [[ -f "${ROOT}/vendor/rev-skills/.claude/skills/re-analyze/SKILL.md" ]] || die "vendor pin missing re-analyze"

    local key
    key="$(bytellm_read_key "${BYTELLM_KEY_FILE}" "${BYTELLM_KEY_LINE}")" || die "empty key on line ${BYTELLM_KEY_LINE} of ${BYTELLM_KEY_FILE}"

    HEADER="$(mktemp)"
    BODY="$(mktemp)"
    REQ="$(mktemp)"
    chmod 600 "${HEADER}" "${BODY}" "${REQ}"
    printf 'Authorization: Bearer %s\n' "${key}" >"${HEADER}"
    key=""
    unset key

    python3 - "${REQ}" "${BYTELLM_MODEL}" "${MARKER}" <<'PY'
import json
import sys

req_path, model, marker = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "model": model,
    "temperature": 1,
    "max_tokens": 1024,
    "messages": [
        {
            "role": "system",
            "content": (
                "You are applying the rev-skills re-analyze entry skill. "
                "The input is a pasted C snippet, so skip environment probe. "
                "Use Level 0 defaults. Authorized evaluation of our own snippet only. "
                "Do not produce exploits, patches, or cracking steps."
            ),
        },
        {
            "role": "user",
            "content": (
                "Snippet:\nint add(int a, int b) { return a + b; }\n\n"
                "Reply with exactly these lines, then one short sentence:\n"
                "RE_OS=unknown\n"
                "RE_GOAL=preliminary\n"
                "RE_DECOMPILER=Ghidra\n"
                "RE_AUTH=owned\n"
                "ROUTE=none\n"
                f"MARKER={marker}\n"
            ),
        },
    ],
}
with open(req_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

    local code
    code="$(curl -sS --noproxy '*' -o "${BODY}" -w '%{http_code}' --connect-timeout 10 \
        --max-time 180 \
        -H "@${HEADER}" \
        -H "Content-Type: application/json" \
        -d "@${REQ}" \
        "${BYTELLM_BASE_URL}/chat/completions")" || true
    if [[ "${code}" != "200" ]]; then
        die "ByteLLM ${BYTELLM_BASE_URL}/chat/completions HTTP ${code}"
    fi
    python3 - "${BODY}" "${MARKER}" "${BYTELLM_MODEL}" <<'PY'
import json
import sys

path, marker, model = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path, encoding="utf-8"))
choice = (data.get("choices") or [None])[0]
if not choice:
    raise SystemExit("no choices in ByteLLM response")
msg = choice.get("message") or {}
text = msg.get("content") or ""
if not text:
    raise SystemExit("empty assistant content")
if marker not in text:
    raise SystemExit("marker missing from model reply")
used = data.get("model") or model
print(f"live_skill_ok model={used}")
print(f"marker_ok {marker}")
for line in text.splitlines():
    stripped = line.strip()
    if stripped.startswith("RE_") or stripped.startswith("ROUTE=") or stripped.startswith("MARKER="):
        print(stripped)
PY
}

main "$@"
